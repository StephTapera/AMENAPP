/**
 * integrationOSFunctions.js
 * AMEN App — Integration OS Cloud Functions
 *
 * Supports the iOS IntegrationOS layer (X1–X7 contracts).
 * All tokens, OAuth secrets, and provider credentials are server-side only.
 * The iOS client never receives a raw token — only opaque session handles.
 *
 * Exported callables:
 *   matchHashedContacts          — privacy-safe contact matching (HMAC hashes only)
 *   getContactDiscoverySalt      — per-user HMAC salt for client-side contact hashing
 *   orgKnowledgeSearch           — full-text search in org knowledge base
 *   orgAssistant                 — AI assistant over org knowledge (Claude, draft-only)
 *   sendEventFollowUpNotification — FCM follow-up for event attendance
 *   sendBroadcast                — multi-channel broadcast (push / SMS / email)
 *   checkBroadcastChannelStatus  — consent + authorization state for a channel
 *   revokeMessagingConsent       — server-authoritative consent revocation
 *   transcribeVoiceNote          — Whisper transcription of a Storage voice note
 *   moderateMediaTransform       — NeMo Guard check on sermon/media text transforms
 *
 * Hard rules:
 *   1. Auth required on every callable.
 *   2. Secrets via Secret Manager / defineSecret — never in responses or logs.
 *   3. Contact hashes are stored only as HMAC-SHA256; plain phone numbers never stored.
 *   4. SMS / email consent must be present in consentLedger before dispatch.
 *   5. orgAssistant outputs are DRAFTS (approved: false) — never auto-published.
 *   6. Minor accounts: contact discovery + SMS + email blocked server-side.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const logger                 = require("firebase-functions/logger");
const admin                  = require("firebase-admin");
const crypto                 = require("crypto");

const db  = () => admin.firestore();
const fcm = () => admin.messaging();

// ─── Secrets ──────────────────────────────────────────────────────────────────
// Declared with defineSecret so the runtime injects them into process.env.
// Twilio secrets are intentionally NOT declared here — they are loaded lazily
// via getSecret() at call time (same pattern as GEMINI_API_KEY in callModel.js).
// This prevents a deploy failure when Twilio credentials are not yet configured.
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const NVIDIA_API_KEY    = defineSecret("NVIDIA_API_KEY");
const OPENAI_API_KEY    = defineSecret("OPENAI_API_KEY");

const { getSecret } = require("./mlClients");

// ─── Shared helpers ───────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

async function getAgeTier(userId) {
  const snap = await db().collection("users").doc(userId).get();
  return snap.data()?.ageTier ?? "adult";
}

async function checkConsent(userId, scope) {
  const entryId = `${userId}_${scope}`;
  const snap = await db()
    .collection("users").doc(userId)
    .collection("consentLedger").doc(entryId)
    .get();
  if (!snap.exists) return false;
  const state = snap.data()?.state;
  return state === "granted";
}

/**
 * sendFcmInChunks — rate-limited bulk FCM sender.
 *
 * FCM's sendEachForMulticast supports up to 500 tokens per call, but AMEN caps
 * bulk sends at 100 tokens/chunk to stay well under FCM quota limits and prevent
 * notification storms.  A 1-second pause between chunks ensures we never exceed
 * ~100 FCM messages/second from a single Cloud Function invocation.
 *
 * @param {object}   messaging   - admin.messaging() instance
 * @param {string[]} tokens      - FCM registration tokens
 * @param {object}   notification - { title, body }
 * @param {object}   data        - arbitrary string-keyed payload
 * @returns {{ successCount: number, failureCount: number }}
 */
async function sendFcmInChunks(messaging, tokens, notification, data) {
  const CHUNK_SIZE = 100;
  let successCount = 0;
  let failureCount = 0;

  const chunks = [];
  for (let i = 0; i < tokens.length; i += CHUNK_SIZE) {
    chunks.push(tokens.slice(i, i + CHUNK_SIZE));
  }

  for (let idx = 0; idx < chunks.length; idx++) {
    const result = await messaging.sendEachForMulticast({
      tokens: chunks[idx],
      notification,
      data,
    });
    successCount += result.successCount;
    failureCount += result.failureCount;

    // Pause between chunks to respect FCM rate limits (skip after the last chunk).
    if (idx < chunks.length - 1) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  return { successCount, failureCount };
}

// ─── matchHashedContacts ──────────────────────────────────────────────────────

exports.matchHashedContacts = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (request) => {
    const uid = requireAuth(request);

    const ageTier = await getAgeTier(uid);
    if (ageTier === "minor") {
      throw new HttpsError("permission-denied", "Contact discovery is not available for this account.");
    }

    const hasConsent = await checkConsent(uid, "contacts.hashed_match");
    if (!hasConsent) {
      throw new HttpsError("failed-precondition", "Contact discovery permission required.");
    }

    const { hashes } = request.data;
    if (!Array.isArray(hashes) || hashes.length === 0) {
      throw new HttpsError("invalid-argument", "hashes must be a non-empty array.");
    }
    if (hashes.length > 500) {
      throw new HttpsError("invalid-argument", "hashes array exceeds 500 item limit.");
    }
    if (!hashes.every(h => typeof h === "string" && /^[a-f0-9]{64}$/.test(h))) {
      throw new HttpsError("invalid-argument", "Each hash must be a 64-char lowercase hex string.");
    }

    // Look up the contactDiscoveryHashes collection — each doc id is a hash of (salt + phone).
    // We return only uids of users who have opted in to contact discovery.
    const batchSize = 30;
    const matchedUids = [];

    for (let i = 0; i < hashes.length; i += batchSize) {
      const chunk = hashes.slice(i, i + batchSize);
      const snap = await db()
        .collection("contactDiscoveryHashes")
        .where(admin.firestore.FieldPath.documentId(), "in", chunk)
        .get();
      snap.forEach(doc => {
        const data = doc.data();
        if (data.optedIn && data.userId && data.userId !== uid) {
          matchedUids.push(data.userId);
        }
      });
    }

    logger.info("matchHashedContacts", { uid, inputCount: hashes.length, matchCount: matchedUids.length });
    return { matchedUids };
  },
);

// ─── getContactDiscoverySalt ──────────────────────────────────────────────────

exports.getContactDiscoverySalt = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 10,
    memory: "256MiB",
  },
  async (request) => {
    const uid = requireAuth(request);

    const ageTier = await getAgeTier(uid);
    if (ageTier === "minor") {
      throw new HttpsError("permission-denied", "Contact discovery is not available for this account.");
    }

    const saltDocRef = db().collection("contactDiscoverySalts").doc(uid);
    const snap = await saltDocRef.get();

    if (snap.exists) {
      return { salt: snap.data().salt };
    }

    // Generate a new per-user HMAC salt (32 random bytes, hex-encoded).
    const salt = crypto.randomBytes(32).toString("hex");
    await saltDocRef.set({ salt, createdAt: admin.firestore.FieldValue.serverTimestamp() });

    logger.info("getContactDiscoverySalt: generated new salt", { uid });
    return { salt };
  },
);

// ─── orgKnowledgeSearch ───────────────────────────────────────────────────────

exports.orgKnowledgeSearch = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    const uid = requireAuth(request);

    const { orgId, query, limit = 20 } = request.data;
    if (!orgId || typeof orgId !== "string") {
      throw new HttpsError("invalid-argument", "orgId is required.");
    }
    if (!query || typeof query !== "string" || query.trim().length === 0) {
      throw new HttpsError("invalid-argument", "query is required.");
    }

    const hasConsent = await checkConsent(uid, "org.knowledge.read");
    if (!hasConsent) {
      throw new HttpsError("failed-precondition", "Org knowledge read permission required.");
    }

    // Verify user is a member of this org
    const memberSnap = await db()
      .collection("organizations").doc(orgId)
      .collection("members").doc(uid)
      .get();
    if (!memberSnap.exists) {
      throw new HttpsError("permission-denied", "You are not a member of this organization.");
    }

    const q = query.trim().toLowerCase();
    const snap = await db()
      .collection("organizations").doc(orgId)
      .collection("knowledgeBase")
      .where("status", "==", "published")
      .orderBy("updatedAt", "desc")
      .limit(Math.min(limit, 50))
      .get();

    const results = snap.docs
      .filter(doc => {
        const data = doc.data();
        return (
          (data.title ?? "").toLowerCase().includes(q) ||
          (data.body ?? "").toLowerCase().includes(q)
        );
      })
      .map(doc => {
        const d = doc.data();
        return {
          id: doc.id,
          title: d.title,
          category: d.category,
          snippet: (d.body ?? "").slice(0, 200),
          updatedAt: d.updatedAt?.toMillis?.() ?? null,
        };
      });

    return { results };
  },
);

// ─── orgAssistant ─────────────────────────────────────────────────────────────

exports.orgAssistant = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 45,
    memory: "256MiB",
    secrets: [ANTHROPIC_API_KEY],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { orgId, question } = request.data;
    if (!orgId || !question) {
      throw new HttpsError("invalid-argument", "orgId and question are required.");
    }
    if (question.length > 1000) {
      throw new HttpsError("invalid-argument", "question exceeds 1000 character limit.");
    }

    const hasConsent = await checkConsent(uid, "org.knowledge.read");
    if (!hasConsent) {
      throw new HttpsError("failed-precondition", "Org knowledge permission required.");
    }

    const memberSnap = await db()
      .collection("organizations").doc(orgId)
      .collection("members").doc(uid)
      .get();
    if (!memberSnap.exists) {
      throw new HttpsError("permission-denied", "You are not a member of this organization.");
    }

    // Fetch up to 5 recent published docs as context
    const ctxSnap = await db()
      .collection("organizations").doc(orgId)
      .collection("knowledgeBase")
      .where("status", "==", "published")
      .orderBy("updatedAt", "desc")
      .limit(5)
      .get();

    const context = ctxSnap.docs
      .map(d => `## ${d.data().title}\n${(d.data().body ?? "").slice(0, 800)}`)
      .join("\n\n---\n\n");

    const systemPrompt = [
      "You are an assistant for a faith organization's internal knowledge base.",
      "Answer questions based only on the provided documents. If the answer is not in the documents, say so clearly.",
      "Be concise, professional, and helpful. Do not fabricate information.",
      "This is a DRAFT response — the user will review before sharing.",
    ].join("\n");

    const userMessage = context
      ? `Organization documents:\n\n${context}\n\n---\n\nQuestion: ${question}`
      : `Question: ${question}\n\n(No documents available in the knowledge base yet.)`;

    const apiKey = ANTHROPIC_API_KEY.value();
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 512,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      }),
    });

    if (!response.ok) {
      logger.error("orgAssistant: Claude error", { status: response.status, uid, orgId });
      return { draft: null, error: "assistant_unavailable" };
    }

    const data = await response.json();
    const draft = data.content?.[0]?.text ?? null;

    logger.info("orgAssistant", { uid, orgId, questionLength: question.length });
    return { draft, approved: false };
  },
);

// ─── sendEventFollowUpNotification ───────────────────────────────────────────

exports.sendEventFollowUpNotification = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (request) => {
    const uid = requireAuth(request);

    const { eventId } = request.data;
    if (!eventId || typeof eventId !== "string") {
      throw new HttpsError("invalid-argument", "eventId is required.");
    }

    // Load event
    const eventSnap = await db().collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }
    const event = eventSnap.data();

    // Only the host can trigger follow-up
    if (event.hostUserId !== uid) {
      throw new HttpsError("permission-denied", "Only the event host can send follow-ups.");
    }

    // Load attendees who RSVPed "going"
    const rsvpSnap = await db()
      .collection("events").doc(eventId)
      .collection("rsvps")
      .where("status", "==", "going")
      .get();

    const attendeeUids = rsvpSnap.docs.map(d => d.data().userId).filter(id => id !== uid);

    if (attendeeUids.length === 0) {
      return { sent: 0 };
    }

    // Batch fetch FCM tokens
    const tokenPromises = attendeeUids.map(attendeeUid =>
      db().collection("users").doc(attendeeUid).get()
    );
    const userDocs = await Promise.all(tokenPromises);

    const tokens = [];
    userDocs.forEach(doc => {
      const fcmToken = doc.data()?.fcmToken;
      if (fcmToken) tokens.push(fcmToken);
    });

    if (tokens.length === 0) {
      return { sent: 0 };
    }

    const result = await sendFcmInChunks(
      fcm(),
      tokens,
      { title: event.title ?? "Event Follow-Up", body: "Thanks for attending! Share how it went." },
      { type: "event_followup", eventId },
    );
    logger.info("sendEventFollowUpNotification", {
      uid, eventId, sent: result.successCount, failed: result.failureCount,
    });

    return { sent: result.successCount };
  },
);

// ─── sendBroadcast ────────────────────────────────────────────────────────────

exports.sendBroadcast = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
    // Twilio secrets loaded lazily via getSecret() — not declared here so deploy
    // succeeds even when Twilio is not yet configured (SMS degrades gracefully).
  },
  async (request) => {
    const uid = requireAuth(request);

    const ageTier = await getAgeTier(uid);
    if (ageTier === "minor") {
      throw new HttpsError("permission-denied", "Broadcast is not available for this account.");
    }

    const { channel, subject, body, recipientUserIds } = request.data;
    if (!channel || !body || !Array.isArray(recipientUserIds) || recipientUserIds.length === 0) {
      throw new HttpsError("invalid-argument", "channel, body, and recipientUserIds are required.");
    }
    if (recipientUserIds.length > 100) {
      throw new HttpsError("invalid-argument", "recipientUserIds exceeds 100 item limit.");
    }
    if (body.length > 1600) {
      throw new HttpsError("invalid-argument", "body exceeds 1600 character limit.");
    }

    // Require sender to have messaging.push consent for push, SMS/email consent for those channels
    const scopeMap = {
      push:  "messaging.push",
      sms:   "messaging.sms",
      email: "messaging.email",
    };
    const requiredScope = scopeMap[channel];
    if (!requiredScope) {
      throw new HttpsError("invalid-argument", `Unknown channel: ${channel}`);
    }

    if (channel === "sms" || channel === "email") {
      const hasConsent = await checkConsent(uid, requiredScope);
      if (!hasConsent) {
        throw new HttpsError("failed-precondition", `${channel} broadcast permission required.`);
      }
    }

    let sent = 0;

    if (channel === "push") {
      const userDocs = await Promise.all(
        recipientUserIds.map(id => db().collection("users").doc(id).get())
      );
      const tokens = userDocs
        .filter(d => d.exists && d.data()?.fcmToken)
        .map(d => d.data().fcmToken);

      if (tokens.length > 0) {
        const result = await sendFcmInChunks(
          fcm(),
          tokens,
          { title: subject ?? "Message from community", body },
          { type: "broadcast", senderId: uid },
        );
        sent = result.successCount;
      }
    } else if (channel === "sms") {
      const [accountSid, authToken, fromNumber] = await Promise.all([
        getSecret("TWILIO_ACCOUNT_SID"),
        getSecret("TWILIO_AUTH_TOKEN"),
        getSecret("TWILIO_FROM_NUMBER"),
      ]);

      if (!accountSid || !authToken || !fromNumber) {
        logger.warn("sendBroadcast: Twilio secrets not configured");
        return { sent: 0, degraded: true };
      }

      const twilio = require("twilio")(accountSid, authToken);

      const userDocs = await Promise.all(
        recipientUserIds.map(id => db().collection("users").doc(id).get())
      );

      for (const doc of userDocs) {
        const phone = doc.data()?.phoneNumber;
        if (!phone) continue;
        const recipientConsent = await checkConsent(doc.id, "messaging.sms");
        if (!recipientConsent) continue;
        try {
          await twilio.messages.create({ body, from: fromNumber, to: phone });
          sent++;
        } catch (err) {
          logger.warn("sendBroadcast: SMS send failed", { to: "REDACTED", err: err.message });
        }
      }
    }

    // Log broadcast to Firestore for audit
    await db().collection("broadcastLogs").add({
      senderId: uid,
      channel,
      recipientCount: recipientUserIds.length,
      sentCount: sent,
      bodyLength: body.length,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("sendBroadcast", { uid, channel, recipients: recipientUserIds.length, sent });
    return { sent };
  },
);

// ─── checkBroadcastChannelStatus ─────────────────────────────────────────────

exports.checkBroadcastChannelStatus = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 10,
    memory: "256MiB",
  },
  async (request) => {
    const uid = requireAuth(request);

    const { channel } = request.data;
    if (!channel || typeof channel !== "string") {
      throw new HttpsError("invalid-argument", "channel is required.");
    }

    const scopeMap = {
      push:  "messaging.push",
      sms:   "messaging.sms",
      email: "messaging.email",
    };

    const scope = scopeMap[channel];
    if (!scope) {
      return { status: "unsupported", authorized: false };
    }

    const ageTier = await getAgeTier(uid);
    if (ageTier === "minor" && (channel === "sms" || channel === "email")) {
      return { status: "blocked_minor", authorized: false };
    }

    const entryId = `${uid}_${scope}`;
    const snap = await db()
      .collection("users").doc(uid)
      .collection("consentLedger").doc(entryId)
      .get();

    const state = snap.exists ? (snap.data()?.state ?? "none") : "none";
    return { status: state, authorized: state === "granted" };
  },
);

// ─── revokeMessagingConsent ───────────────────────────────────────────────────

exports.revokeMessagingConsent = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 10,
    memory: "256MiB",
  },
  async (request) => {
    const uid = requireAuth(request);

    const { channel } = request.data;
    const scopeMap = {
      push:  "messaging.push",
      sms:   "messaging.sms",
      email: "messaging.email",
    };

    const scope = scopeMap[channel];
    if (!scope) {
      throw new HttpsError("invalid-argument", `Unknown channel: ${channel}`);
    }

    const entryId = `${uid}_${scope}`;
    await db()
      .collection("users").doc(uid)
      .collection("consentLedger").doc(entryId)
      .set(
        {
          state: "revoked",
          revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    logger.info("revokeMessagingConsent", { uid, channel, scope });
    return { success: true };
  },
);

// ─── transcribeVoiceNote ──────────────────────────────────────────────────────

exports.transcribeVoiceNote = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: [OPENAI_API_KEY],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { storagePath, mimeType = "audio/m4a" } = request.data;
    if (!storagePath || typeof storagePath !== "string") {
      throw new HttpsError("invalid-argument", "storagePath is required.");
    }

    // Security: storagePath must be under the caller's uid prefix
    if (!storagePath.startsWith(`voiceNotes/${uid}/`) && !storagePath.startsWith(`users/${uid}/voiceNotes/`)) {
      throw new HttpsError("permission-denied", "Access denied to this storage path.");
    }

    const apiKey = OPENAI_API_KEY.value();
    if (!apiKey) {
      return { transcript: null, error: "transcription_unavailable" };
    }

    // Download the file from Cloud Storage
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);

    let audioBuffer;
    try {
      const [contents] = await file.download();
      audioBuffer = contents;
    } catch (err) {
      logger.error("transcribeVoiceNote: download failed", { uid, storagePath, err: err.message });
      throw new HttpsError("not-found", "Voice note file not found.");
    }

    // Call OpenAI Whisper via multipart form
    const FormData = require("form-data");
    const form = new FormData();
    form.append("file", audioBuffer, { filename: "audio.m4a", contentType: mimeType });
    form.append("model", "whisper-1");
    form.append("language", "en");

    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        ...form.getHeaders(),
      },
      body: form,
    });

    if (!response.ok) {
      logger.error("transcribeVoiceNote: Whisper error", { status: response.status, uid });
      return { transcript: null, error: "transcription_unavailable" };
    }

    const data = await response.json();
    const transcript = data.text ?? null;

    logger.info("transcribeVoiceNote", { uid, storagePath, transcriptLength: transcript?.length ?? 0 });
    return { transcript };
  },
);

// ─── moderateMediaTransform ───────────────────────────────────────────────────

exports.moderateMediaTransform = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 20,
    memory: "256MiB",
    secrets: [NVIDIA_API_KEY],
  },
  async (request) => {
    const uid = requireAuth(request);

    const { text, mediaObjectId } = request.data;
    if (!text || typeof text !== "string") {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > 4000) {
      throw new HttpsError("invalid-argument", "text exceeds 4000 character limit.");
    }

    const apiKey = NVIDIA_API_KEY.value();
    if (!apiKey) {
      // Fail closed — never approve without a guard check
      logger.warn("moderateMediaTransform: NVIDIA_API_KEY unavailable — returning pending", { uid });
      return { decision: "pending", categories: [] };
    }

    const NIM_URL   = "https://integrate.api.nvidia.com/v1/chat/completions";
    const NIM_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

    const response = await fetch(NIM_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: NIM_MODEL,
        messages: [
          {
            role: "system",
            content: "You are a content safety classifier for a faith community app. Review the following sermon or media analysis text for harmful content.",
          },
          { role: "user", content: text },
        ],
        max_tokens: 256,
        temperature: 0.0,
      }),
    });

    if (!response.ok) {
      logger.warn("moderateMediaTransform: NIM error — failing closed", { status: response.status, uid });
      return { decision: "pending", categories: [] };
    }

    const data = await response.json();
    const reply = (data.choices?.[0]?.message?.content ?? "").toLowerCase();

    // Simple safe/unsafe classification from the guard response
    const isSafe = !reply.includes("unsafe") && !reply.includes("harmful") && !reply.includes("violat");
    const decision = isSafe ? "approved" : "review";

    if (mediaObjectId) {
      await db().collection("mediaTransformModerations").doc(mediaObjectId).set({
        userId: uid,
        decision,
        checkedAt: admin.firestore.FieldValue.serverTimestamp(),
        textLength: text.length,
      }, { merge: true });
    }

    logger.info("moderateMediaTransform", { uid, mediaObjectId, decision });
    return { decision, categories: isSafe ? [] : ["content_review"] };
  },
);
