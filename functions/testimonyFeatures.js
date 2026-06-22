const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten, onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");

const db = admin.firestore();

/**
 * cleanStaleWitnesses — runs every 60 seconds, deletes witness presence docs
 * older than 60 seconds from all active subcollections.
 */
exports.cleanStaleWitnesses = onSchedule(
  { schedule: "every 1 minutes", timeoutSeconds: 30 },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );
    const witnessesRef = db.collection("witnesses");
    const postSnap = await witnessesRef.listDocuments();

    const batchOps = [];
    for (const postDoc of postSnap) {
      const activeSnap = await postDoc.collection("active")
        .where("timestamp", "<", cutoff)
        .get();
      for (const doc of activeSnap.docs) {
        batchOps.push(doc.ref.delete());
      }
    }
    await Promise.all(batchOps);
    console.log(`cleanStaleWitnesses: deleted ${batchOps.length} stale docs`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// SECURITY (H8 fix): NeMo Guard helper for testimony text moderation.
// Mirrors the checkSafety pattern in moderatePost.js.
// Fails closed: any NIM error, network failure, or parse ambiguity → safe = false.
// ─────────────────────────────────────────────────────────────────────────────
const TESTIMONY_NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const TESTIMONY_SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";
const TESTIMONY_NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");
const TTL_TESTIMONY_PENDING_MS = 90 * 24 * 60 * 60 * 1000;

const TESTIMONY_SELF_HARM_PHRASES = [
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
function detectTestimonySelfHarm(text) {
  const lower = text.toLowerCase();
  return TESTIMONY_SELF_HARM_PHRASES.some((p) => lower.includes(p));
}

async function checkTestimonySafety(text) {
  const apiKey = process.env.NVIDIA_API_KEY;
  const delays = [500, 1000, 2000];
  let res = null;

  for (let attempt = 0; attempt <= 3; attempt++) {
    try {
      res = await fetch(TESTIMONY_NIM_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: TESTIMONY_SAFETY_MODEL,
          messages: [{ role: "user", content: text }],
          max_tokens: 100,
          temperature: 0,
        }),
      });
    } catch (err) {
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, delays[Math.min(attempt, delays.length - 1)]));
        continue;
      }
      throw new Error(`[moderateTestimony] NIM fetch failed: ${err.message}`);
    }
    if (res.status === 429 || res.status >= 500) {
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, delays[Math.min(attempt, delays.length - 1)]));
        continue;
      }
      throw new Error(`[moderateTestimony] NIM ${res.status} after 3 retries`);
    }
    break;
  }

  if (!res || !res.ok) {
    throw new Error(`[moderateTestimony] NIM non-OK: ${res ? res.status : "no response"}`);
  }

  const data = await res.json();
  const raw = data.choices?.[0]?.message?.content ?? "";

  // Jailbreak-resistant parsing — fail closed.
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && "User Safety" in parsed) {
      const safe = String(parsed["User Safety"]).trim().toLowerCase() === "safe";
      const categories = parsed["Safety Categories"]
        ? String(parsed["Safety Categories"]).split(",").map((c) => c.trim().toLowerCase()).filter(Boolean)
        : [];
      return { safe, categories };
    }
    return { safe: false, categories: [] };
  } catch {
    return { safe: false, categories: ["parse_error"] };
  }
}

/**
 * updateTestimonyStrength — triggers on writes to posts/{postId}.
 * Recomputes testimonyStrength from sub-signals and writes it back.
 */
exports.updateTestimonyStrength = onDocumentWritten(
  "posts/{postId}",
  async (event) => {
    const data = event.data?.after?.data();
    if (!data) return;
    if (data.category !== "testimonies") return;

    const postId = event.params.postId;

    // Gather signals
    const witnessCount    = data.witnessCount    || 0;
    const prayerEchoCount = data.prayerEchoCount || 0;
    const scriptureCount  = data.scriptureCount  || 0;
    const amenCount       = data.amenCount        || 0;
    const neededCount     = data.neededCount      || 0;

    // Score calculation
    let score = 0;
    score += witnessCount    * 10;   // each witness tap
    score += prayerEchoCount * 12;   // prayer echoes
    score += scriptureCount  * 15;   // scripture references in replies
    score += amenCount       * 5;    // claps/amens
    score += neededCount     * 5;    // needed this
    score = Math.min(100, score);

    // Don't write if unchanged (avoid trigger loop)
    if ((data.testimonyStrength || 0) === score) return;

    const update = { testimonyStrength: score };

    // Milestone: hit 100 → write to milestones collection
    if (score >= 100 && (data.testimonyStrength || 0) < 100) {
      await db.collection("milestones").add({
        postId,
        authorId: data.authorId,
        type: "testimonyStrengthMax",
        achievedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return db.collection("posts").doc(postId).update(update);
  }
);

/**
 * onNeededThisWrite — triggers when neededCount increments on a post.
 * At 10+: sends FCM push to testimony author.
 */
exports.onNeededThisWrite = onDocumentUpdated(
  "posts/{postId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    if (!before || !after) return;
    if (after.category !== "testimonies") return;

    const neededBefore = before.neededCount || 0;
    const neededAfter  = after.neededCount  || 0;

    // Only act when incrementing past threshold
    if (neededAfter < 10 || neededBefore >= 10) return;

    const authorId = after.authorId;
    if (!authorId) return;

    // Fetch author tokens
    const userDoc = await db.collection("users").doc(authorId).get();
    const tokens = userDoc.data()?.fcmTokens || [];
    if (!tokens.length) return;

    const postId = event.params.postId;

    // Send push
    const message = {
      notification: {
        title: "Your testimony is reaching people",
        body: "10 people saved your testimony — keep sharing.",
      },
      data: { type: "neededThis", postId },
    };
    await admin.messaging().sendEachForMulticast({ tokens, ...message });

    // Write to weekly digest
    await db.collection("weeklyDigest").doc(authorId)
      .collection("items").add({
        type: "neededThis",
        postId,
        count: neededAfter,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// moderateTestimony — SECURITY (H8 fix)
//
// Fires on every new testimony document written to the `testimonies/` collection.
// Screens the body field through NeMo Guard before the testimony becomes visible.
//
// Outcome:
//   safe     → visible: true, moderation.status: "approved"
//   unsafe   → visible: false, removed: true, moderationQueue entry created
//   NIM error → fail closed: visible: false, status: "pending", moderationQueue entry
//   self-harm → visible: false, status: "pending_crisis", moderationQueue (priority: critical)
//
// Deploy: firebase deploy --only functions:moderateTestimony --project amen-5e359
// Secret: NVIDIA_API_KEY (already set for moderatePost / moderateUGC)
// ─────────────────────────────────────────────────────────────────────────────
exports.moderateTestimony = onDocumentCreated(
  {
    document: "testimonies/{testimonyId}",
    secrets: [TESTIMONY_NVIDIA_API_KEY],
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const testimony = snap.data();
    const text = (testimony.body || testimony.text || testimony.content || "").trim();
    const authorId = testimony.authorId || testimony.userId || null;
    const testimonyId = event.params.testimonyId;

    // Empty testimony body — route to pending review so it is not silently published.
    if (!text) {
      await snap.ref.update({
        visible: false,
        moderation: {
          status: "pending",
          categories: [],
          provider: "nvidia-nemoguard",
          checkedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
      await db.collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "testimony",
        authorId,
        preview: "[no body text — pending review]",
        status: "pending",
        categories: [],
        priority: "normal",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_TESTIMONY_PENDING_MS),
      });
      console.log(`[moderateTestimony] Empty body for ${testimonyId} — routed to review`);
      return;
    }

    const selfHarm = detectTestimonySelfHarm(text);

    let status;
    let categories = [];
    try {
      const verdict = await checkTestimonySafety(text);
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      // Fail closed: NIM unavailable → pending review, never auto-approve.
      console.error("[moderateTestimony] NIM call failed — failing closed:", err.message);
      status = "pending";
    }

    // Self-harm testimony: must never be silently blocked — route to crisis review.
    if (selfHarm) {
      status = "pending_crisis";
    }

    const moderationBatch = db.batch();

    moderationBatch.update(snap.ref, {
      visible: status === "approved",
      removed: status === "blocked",
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: admin.firestore.FieldValue.serverTimestamp(),
        crisisEscalated: selfHarm,
      },
    });

    if (status !== "approved") {
      const queueRef = db.collection("moderationQueue").doc();
      moderationBatch.set(queueRef, {
        contentRef: snap.ref.path,
        contentType: "testimony",
        authorId,
        preview: text.slice(0, 280),
        status,
        categories,
        crisisEscalated: selfHarm,
        priority: selfHarm ? "critical" : "normal",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_TESTIMONY_PENDING_MS),
      });
    }

    await moderationBatch.commit();

    console.log(
      `[moderateTestimony] testimonyId=${testimonyId} authorId=${authorId} status=${status}` +
        (selfHarm ? " [CRISIS]" : "") +
        (categories.length ? ` categories=${categories.join(",")}` : ""),
    );
  }
);
