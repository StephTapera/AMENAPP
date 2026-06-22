// moderateUGC.js — v1 Cloud Functions (avoids Cloud Run quota)
// NVIDIA_API_KEY is injected via runWith({ secrets: ["NVIDIA_API_KEY"] }) — Gen1 Secret Manager pattern.
// Server-side onCreate moderation triggers for Sanctuary messages, prayer requests,
// and DM messages. Reuses the same NVIDIA NeMo Guard pipeline as moderatePost.js.
// All three triggers fail closed: if the NIM call errors, the document is hidden
// and queued for admin review.

const functions = require("firebase-functions/v1");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { withRetry } = require("./retryHelper");

// SECURITY (C2 fix 2026-06-11): Image-only messages (DMs, sanctuary messages) must
// also run vision moderation so CSAM images in those surfaces reach the same
// escalation pipeline as post images.
const { moderateImage } = require("./moderation/imageModeration");
const { fileNCMECReport } = require("./ncmecReporter");
const IMAGE_CSAM_CATEGORIES_UGC = new Set(["cs_csam_suspected", "cs_child_exploitation"]);

// SECURITY (H7 fix 2026-06-11): Wire the grooming-pattern detector so adult→minor
// DM streams are actually analysed. Import detectGroomingRisk and the interaction
// checker here so moderateDMMessage can invoke them on every new DM.
const { detectGroomingRisk, checkAdultMinorInteraction } = require("./safety/minorProtection");

// Number of prior messages to fetch for grooming-pattern analysis. Kept small to
// minimise Firestore reads while still catching multi-turn patterns.
const GROOMING_CONTEXT_WINDOW = 20;

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
      // SECURITY (C2 fix 2026-06-11): Run vision moderation on image-only sanctuary
      // messages so CSAM images reach the mandatory escalation pipeline.
      const sanctuaryImageUrl = message.imageUrl || message.mediaUrl || null;
      const sanctuaryAuthorId = message.senderId || message.authorId || null;
      let sanctuaryImgResult = null;
      if (sanctuaryImageUrl) {
        try {
          sanctuaryImgResult = await moderateImage(sanctuaryImageUrl, process.env.NVIDIA_API_KEY);
        } catch (imgErr) {
          console.warn(`[moderateSanctuaryMessage] moderateImage failed (${imgErr.message}) — failing closed`);
          sanctuaryImgResult = null;
        }
      }

      const sanctuaryImgCategories = sanctuaryImgResult ? sanctuaryImgResult.categories : [];
      const sanctuaryImgHasCSAM = sanctuaryImgCategories.some((c) => IMAGE_CSAM_CATEGORIES_UGC.has(c));

      if (sanctuaryImgHasCSAM) {
        const db = getFirestore();
        const holdId = `hold_sanc_${snap.id}_${Date.now()}`;
        const holdRef = db.collection("legalHolds").doc(holdId);
        const escRef = db.collection("childSafetyEscalations").doc();
        const sanctuaryCsamBatch = db.batch();

        sanctuaryCsamBatch.update(snap.ref, {
          visible: false,
          moderation: {
            status: "blocked",
            categories: sanctuaryImgCategories,
            provider: "nvidia-vision-llm",
            checkedAt: FieldValue.serverTimestamp(),
            childSafetyEscalated: true,
          },
        });

        sanctuaryCsamBatch.set(holdRef, {
          contentRef: snap.ref.path,
          authorId: sanctuaryAuthorId ?? null,
          contentSnapshot: message,
          categories: sanctuaryImgCategories,
          createdAt: FieldValue.serverTimestamp(),
          status: "active",
        });

        sanctuaryCsamBatch.set(escRef, {
          contentRef: snap.ref.path,
          authorId: sanctuaryAuthorId ?? null,
          categories: sanctuaryImgCategories,
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

        await sanctuaryCsamBatch.commit();

        await fileNCMECReport({
          contentRef: snap.ref.path,
          contentType: "sanctuary_image",
          contentUrl: sanctuaryImageUrl,
          authorId: sanctuaryAuthorId ?? null,
          detectedCategories: sanctuaryImgCategories,
          detectedBy: "nvidia-vision-llm",
        }).catch((e) => console.error("[moderateSanctuaryMessage] fileNCMECReport error (CSAM):", e.message));

        console.warn(
          `[moderateSanctuaryMessage] SANCTUARY IMAGE CSAM ESCALATED — msg ${snap.id} categories: ${sanctuaryImgCategories.join(", ")}`,
        );
        return;
      }

      // Non-CSAM: route to human review queue as before.
      await snap.ref.update({
        visible: false,
        moderation: {
          status: "pending_image_review",
          categories: sanctuaryImgCategories,
          provider: sanctuaryImgResult ? "nvidia-vision-llm" : "image-review-pending",
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "sanctuary_message",
        sanctuaryId: context.params.sanctuaryId,
        authorId: sanctuaryAuthorId,
        preview: "[media-only message — pending visual review]",
        status: "pending",
        categories: sanctuaryImgCategories,
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

    // SECURITY FIX (LOW 2026-06-11): Use a Firestore batch for the moderation-status
    // update and moderationQueue.add to make them atomic. The previous separate awaits
    // could leave the message with its moderation status set but without a queue entry
    // if the function timed out between the two writes, making it invisible to the
    // admin review panel. Batch ensures both succeed or both are not written.
    const db = getFirestore();
    const batch = db.batch();

    batch.update(snap.ref, {
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
      const queueRef = db.collection("moderationQueue").doc();
      batch.set(queueRef, {
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

    await batch.commit();

    // Persist to moderationDecisions/ and (if self-harm) crisisEscalations/ — outside
    // the batch because persistUGCDecision handles its own writes and error handling.
    await persistUGCDecision(
      authorId,
      "sanctuary_message",
      snap.ref.path,
      status,
      categories,
      selfHarm,
      text
    );
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

    // SECURITY FIX (MEDIUM 2026-06-11): Use a Firestore batch so that the
    // moderation-status update and moderationQueue write are atomic. A function
    // crash between the two sequential awaits previously left a blocked/pending
    // prayer visible in Firestore but absent from the admin review queue.
    const db = getFirestore();
    const batch = db.batch();

    batch.update(snap.ref, {
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

    if (status !== "approved") {
      const queueRef = db.collection("moderationQueue").doc();
      batch.set(queueRef, {
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

    await batch.commit();

    // Persist to moderationDecisions/ and (if self-harm) crisisEscalations/ — outside
    // the batch because persistUGCDecision handles its own writes and error handling.
    await persistUGCDecision(
      authorId,
      "prayer_request",
      snap.ref.path,
      status,
      categories,
      selfHarm,
      text
    );
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
      // SECURITY (DM video gap, 2026-06-21): video DMs are written by
      // VideoAttachmentHandler with messageType "video" + a `mediaURL` field that
      // the image path below does NOT recognize, so video content was never scanned.
      // We cannot run vision moderation on a raw video URL here (no frame
      // extraction). Fail closed: hold the message (not visible) and flag it as an
      // unmoderated video for the review pipeline rather than letting video content
      // reach the recipient unscanned. (Delivery is unchanged — such messages were
      // already held under pending_image_review; this only makes the hold explicit.)
      const isVideo =
        message.messageType === "video" ||
        (!!message.mediaURL && !message.imageUrl && !message.mediaUrl);
      if (isVideo) {
        await snap.ref.update({
          visible: false,
          moderation: {
            status: "pending_video_review",
            categories: [],
            provider: "video-review-pending",
            unmoderatedVideo: true,
            checkedAt: FieldValue.serverTimestamp(),
          },
        });
        console.warn(
          `[moderateDMMessage] DM VIDEO held for review — no automated video ` +
          `moderation available; msg ${snap.id}`,
        );
        return;
      }

      // SECURITY (C2 fix 2026-06-11): Run vision moderation on image-only DMs so CSAM
      // in direct messages reaches the mandatory escalation pipeline rather than
      // silently sitting in pending_image_review with no legalHold or NCMEC entry.
      const imageUrl = message.imageUrl || message.mediaUrl || null;
      let dmImgResult = null;
      if (imageUrl) {
        try {
          dmImgResult = await moderateImage(imageUrl, process.env.NVIDIA_API_KEY);
        } catch (imgErr) {
          console.warn(`[moderateDMMessage] moderateImage failed (${imgErr.message}) — failing closed`);
          dmImgResult = null;
        }
      }

      const dmImgCategories = dmImgResult ? dmImgResult.categories : [];
      const dmImgHasCSAM = dmImgCategories.some((c) => IMAGE_CSAM_CATEGORIES_UGC.has(c));

      if (dmImgHasCSAM) {
        // Mandatory escalation: hide + legalHold + childSafetyEscalations + NCMEC queue.
        const db = getFirestore();
        const holdId = `hold_dm_${snap.id}_${Date.now()}`;
        const holdRef = db.collection("legalHolds").doc(holdId);
        const escRef = db.collection("childSafetyEscalations").doc();
        const csamBatch = db.batch();

        csamBatch.update(snap.ref, {
          visible: false,
          moderation: {
            status: "blocked",
            categories: dmImgCategories,
            provider: "nvidia-vision-llm",
            checkedAt: FieldValue.serverTimestamp(),
            childSafetyEscalated: true,
          },
        });

        csamBatch.set(holdRef, {
          contentRef: snap.ref.path,
          authorId: authorId ?? null,
          contentSnapshot: message,
          categories: dmImgCategories,
          createdAt: FieldValue.serverTimestamp(),
          status: "active",
        });

        csamBatch.set(escRef, {
          contentRef: snap.ref.path,
          authorId: authorId ?? null,
          categories: dmImgCategories,
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

        await csamBatch.commit();

        await fileNCMECReport({
          contentRef: snap.ref.path,
          contentType: "dm_image",
          contentUrl: imageUrl,
          authorId: authorId ?? null,
          detectedCategories: dmImgCategories,
          detectedBy: "nvidia-vision-llm",
        }).catch((e) => console.error("[moderateDMMessage] fileNCMECReport error (CSAM):", e.message));

        console.warn(
          `[moderateDMMessage] DM IMAGE CSAM ESCALATED — msg ${snap.id} categories: ${dmImgCategories.join(", ")}`,
        );
        return;
      }

      // Non-CSAM image-only DM: route to pending_image_review as before.
      await snap.ref.update({
        visible: false,
        moderation: {
          status: "pending_image_review",
          categories: dmImgCategories,
          provider: dmImgResult ? "nvidia-vision-llm" : "image-review-pending",
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

    // SECURITY FIX (MEDIUM 2026-06-11): Use a Firestore batch so that the
    // moderation-status update and moderationQueue write are atomic, matching
    // the pattern in moderateSanctuaryMessage.
    const dmDb = getFirestore();
    const dmBatch = dmDb.batch();

    dmBatch.update(snap.ref, {
      visible: status === "approved",
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
        crisisEscalated: selfHarm,
      },
    });

    if (status !== "approved") {
      const dmQueueRef = dmDb.collection("moderationQueue").doc();
      dmBatch.set(dmQueueRef, {
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

    await dmBatch.commit();

    // Persist to moderationDecisions/ and (if self-harm) crisisEscalations/ — outside
    // the batch because persistUGCDecision handles its own writes and error handling.
    await persistUGCDecision(
      authorId,
      "dm_message",
      snap.ref.path,
      status,
      categories,
      selfHarm,
      text
    );

    // ── SECURITY (H7 fix 2026-06-11): Grooming-pattern analysis ──────────────
    // Run detectGroomingRisk on every new DM in a conversation that involves an
    // adult↔minor pair.  This was the critical gap: the function existed and was
    // exported but was never called, so grooming signals produced no alert.
    //
    // Strategy:
    //   1. Identify whether this conversation involves a mixed adult/minor pair by
    //      calling checkAdultMinorInteraction (which reads both users' safety docs).
    //      We only pay the Firestore lookup cost when needed.
    //   2. If it is mixed, fetch the last GROOMING_CONTEXT_WINDOW messages and
    //      annotate each with isAdult / isMinorRecipient metadata.
    //   3. Pass the annotated messages to detectGroomingRisk.
    //   4. If risk >= "elevated" (high | critical), write a safetyAlert and a
    //      moderationQueue entry — never weaken an existing "blocked" status.
    if (authorId) {
      try {
        const groomDb = getFirestore();
        const convData = (
          await groomDb.collection("conversations").doc(context.params.conversationId).get()
        ).data();

        if (convData) {
          const participantIds = convData.participantIds || [];
          // Only analyse direct (non-group) conversations to limit scope.
          const recipients = participantIds.filter((id) => id !== authorId);
          if (recipients.length === 1) {
            const recipientId = recipients[0];

            // checkAdultMinorInteraction reads both safety docs and tells us
            // whether this is a mixed adult/minor pair without us having to
            // replicate the age-resolution logic here.
            const interactionCheck = await checkAdultMinorInteraction(
              groomDb,
              authorId,
              recipientId,
              "dm"
            );

            // We run grooming analysis even when the DM was blocked — the pattern
            // data is still valuable for moderation context.  We also run on
            // age_unknown cases (fail-safe: treat as potentially minor).
            const isMixedOrUnknown =
              interactionCheck.reason === "adult_minor_dm_blocked" ||
              interactionCheck.reason === "age_unknown_dm_blocked" ||
              interactionCheck.reason === "age_unknown_pending_review";

            if (isMixedOrUnknown) {
              // Fetch the N most recent messages for pattern context.
              const priorSnaps = await groomDb
                .collection("conversations")
                .doc(context.params.conversationId)
                .collection("messages")
                .orderBy("createdAt", "desc")
                .limit(GROOMING_CONTEXT_WINDOW)
                .get();

              // Resolve which UID is the adult and which is the minor so we can
              // annotate messages correctly.  When ages are unknown we treat the
              // sender as adult (worst-case assumption for grooming detection).
              const senderUserDoc = await groomDb.collection("users").doc(authorId).get();
              const senderData = senderUserDoc.data() || {};
              const senderIsAdult =
                senderData.ageTier === "adult" ||
                (senderData.safety && senderData.safety.isMinor === false);

              const annotatedMessages = priorSnaps.docs.map((d) => {
                const m = d.data();
                const msgSender = m.senderId || "";
                const isAdult = msgSender === authorId ? senderIsAdult : !senderIsAdult;
                const isMinorRecipient = !isAdult;
                return {
                  senderUid: msgSender,
                  isAdult: !!isAdult,
                  isMinorRecipient: !!isMinorRecipient,
                  text: (m.text || m.content || "").trim(),
                };
              });

              const { risk, flags } = detectGroomingRisk(annotatedMessages);

              if (risk === "high" || risk === "critical") {
                const alertId = `grm_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
                const alertRef = groomDb.collection("safetyAlerts").doc(alertId);
                const mqRef = groomDb.collection("moderationQueue").doc(alertId);

                const groomBatch = groomDb.batch();

                groomBatch.set(alertRef, {
                  id: alertId,
                  type: "grooming_risk_detected",
                  conversationId: context.params.conversationId,
                  senderUid: authorId,
                  recipientUid: recipientId,
                  risk,
                  flags,
                  triggerMessageRef: snap.ref.path,
                  timestamp: FieldValue.serverTimestamp(),
                });

                groomBatch.set(mqRef, {
                  type: "grooming_risk",
                  conversationId: context.params.conversationId,
                  senderUid: authorId,
                  recipientUid: recipientId,
                  risk,
                  flags,
                  triggerMessageRef: snap.ref.path,
                  priority: risk === "critical" ? "critical" : "high",
                  status: "pending",
                  createdAt: FieldValue.serverTimestamp(),
                  expireAt: new Date(Date.now() + TTL_PENDING_MS),
                });

                await groomBatch.commit();

                console.warn(
                  `[moderateDMMessage] GROOMING RISK ${risk.toUpperCase()} detected — ` +
                  `conv ${context.params.conversationId} flags: ${flags.join(", ")}`
                );
              }
            }
          }
        }
      } catch (groomErr) {
        // Grooming analysis must never silently swallow errors that could indicate
        // a data integrity problem — log loudly but do not throw so the rest of
        // the moderation pipeline is unaffected.
        console.error("[moderateDMMessage] groomingRisk analysis error:", groomErr.message);
      }
    }
    // ── End grooming-pattern analysis ────────────────────────────────────────
  });
