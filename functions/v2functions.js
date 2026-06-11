/**
 * v2functions.js
 * All gen-2 (Firebase Functions v2) inline trigger definitions.
 * Kept in a separate file so that index.js (which contains gen-1 functions)
 * does not import v2 SDKs — the Firebase CLI infers generation from the SDK
 * used per-file, and mixing imports caused it to apply v2 CPU/concurrency
 * settings to the gen-1 cancelAllSubscriptions and stripeWebhook functions.
 */

const admin = require("firebase-admin");
const {onValueCreated} = require("firebase-functions/v2/database");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");

const BIBLE_API_KEY = defineSecret("BIBLE_API_KEY");

function isSundayForUser(uid) {
  return require("./shabbatMiddleware").isSundayForUser(uid);
}

// ============================================================================
// REALTIME DATABASE: COMMENT + REPLY NOTIFICATIONS (merged single trigger)
// Previously two separate triggers fired on every write to the same RTDB path,
// each short-circuiting on parentId. Merged into one to halve invocation cost.
// ============================================================================

exports.onRealtimeCommentCreate = onValueCreated(
    {
      ref: "/postInteractions/{postId}/comments/{commentId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const commentId = event.params.commentId;
      const commentData = event.data.val();
      const isReply = !!commentData.parentId;

      console.log(`${isReply ? "💬 New reply" : "📝 New comment"} on post ${postId}: ${commentId}`);

      try {
        const authorId = commentData.userId;

        // ── Shabbat guard ────────────────────────────────────────────────
        if (await isSundayForUser(authorId)) {
          console.log(`🕊️ Shabbat Mode active for ${authorId} — skipping notification`);
          return null;
        }

        if (isReply) {
          // ── Reply branch ──────────────────────────────────────────────
          const parentSnap = await admin.database()
              .ref(`postInteractions/${postId}/comments/${commentData.parentId}`)
              .once("value");
          if (!parentSnap.exists()) {
            console.log("⚠️ Parent comment not found");
            return null;
          }
          const parentAuthorId = parentSnap.val().userId;
          if (parentAuthorId === authorId) {
            console.log("⏭️ Skipping - user replied to their own comment");
            return null;
          }

          const actorDoc = await admin.firestore().collection("users").doc(authorId).get();
          const actorData = actorDoc.data();
          const actorName = actorData?.displayName || "Someone";
          const actorProfileImageURL = actorData?.profileImageURL || actorData?.profilePictureURL || "";

          await admin.firestore()
              .collection("users").doc(parentAuthorId).collection("notifications")
              .add({
                type: "reply",
                actorId: authorId,
                actorName,
                actorUsername: actorData?.username || "",
                actorProfileImageURL,
                postId,
                commentText: commentData.content || commentData.text || "",
                userId: parentAuthorId,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
          console.log(`✅ Reply notification created for user ${parentAuthorId}`);

          const recipientDoc = await admin.firestore().collection("users").doc(parentAuthorId).get();
          const fcmToken = recipientDoc.data()?.fcmToken;
          if (fcmToken) {
            await admin.messaging().send({
              notification: { title: "New Reply", body: `${actorName} replied to your comment` },
              data: { type: "reply", actorId: authorId, postId },
              token: fcmToken,
            });
          }
        } else {
          // ── Top-level comment branch ──────────────────────────────────
          const postDoc = await admin.firestore().collection("posts").doc(postId).get();
          if (!postDoc.exists) {
            console.log("⚠️ Post not found");
            return null;
          }
          const postAuthorId = postDoc.data().userId;
          if (postAuthorId === authorId) {
            console.log("⏭️ Skipping - user commented on their own post");
            return null;
          }

          const actorDoc = await admin.firestore().collection("users").doc(authorId).get();
          const actorData = actorDoc.data();
          const actorName = actorData?.displayName || "Someone";
          const actorProfileImageURL = actorData?.profileImageURL || actorData?.profilePictureURL || "";

          await admin.firestore()
              .collection("users").doc(postAuthorId).collection("notifications")
              .add({
                type: "comment",
                actorId: authorId,
                actorName,
                actorUsername: actorData?.username || "",
                actorProfileImageURL,
                postId,
                commentText: commentData.content || commentData.text || "",
                userId: postAuthorId,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
          console.log(`✅ Comment notification created for user ${postAuthorId}`);

          const recipientDoc = await admin.firestore().collection("users").doc(postAuthorId).get();
          const fcmToken = recipientDoc.data()?.fcmToken;
          if (fcmToken) {
            await admin.messaging().send({
              notification: { title: "New Comment", body: `${actorName} commented on your post` },
              data: { type: "comment", actorId: authorId, postId },
              token: fcmToken,
            });
          }
        }

        return { success: true };
      } catch (error) {
        console.error("❌ Error in onRealtimeCommentCreate:", error);
        return null;
      }
    },
);

// ============================================================================
// FIRESTORE: MESSAGE NOTIFICATIONS
// ============================================================================

/**
 * Triggers when a new message is sent in a conversation
 * Path: conversations/{conversationId}/messages/{messageId}
 */
exports.onMessageSent = onDocumentCreated(
    {
      document: "conversations/{conversationId}/messages/{messageId}",
      region: "us-central1",
    },
    async (event) => {
      const conversationId = event.params.conversationId;
      const messageId = event.params.messageId;
      const messageData = event.data.data();

      console.log(`💬 New message in conversation ${conversationId}: ${messageId}`);

      try {
        const senderId = messageData.senderId;

        // ── Shabbat guard ────────────────────────────────────────────────
        if (await isSundayForUser(senderId)) {
          console.log(`🕊️ Shabbat Mode active for ${senderId} — skipping message notification`);
          return null;
        }
        // ────────────────────────────────────────────────────────────────
        const messageText = messageData.text || "";

        // Get conversation to find recipients
        const conversationDoc = await admin.firestore()
            .collection("conversations")
            .doc(conversationId)
            .get();

        if (!conversationDoc.exists) {
          console.log("⚠️ Conversation not found");
          return null;
        }

        const conversationData = conversationDoc.data();
        const participantIds = conversationData.participantIds || [];
        const conversationStatus = conversationData.conversationStatus || "accepted";
        const isGroup = conversationData.isGroup || false;
        const groupName = conversationData.groupName;

        // Get sender info
        const senderDoc = await admin.firestore()
            .collection("users")
            .doc(senderId)
            .get();

        const senderData = senderDoc.data();
        const senderName = senderData?.displayName || "Someone";
        const senderIsPrivate = senderData?.isPrivateAccount || false;

        // Send notification to all participants except sender
        const recipients = participantIds.filter((id) => id !== senderId);

        for (const recipientId of recipients) {
          const recipientDoc = await admin.firestore()
              .collection("users")
              .doc(recipientId)
              .get();

          const recipientData = recipientDoc.data();
          const recipientIsPrivate = recipientData?.isPrivateAccount || false;

          const senderBlockedUsers = senderData?.blockedUsers || [];
          const recipientBlockedUsers = recipientData?.blockedUsers || [];
          const isBlocked = senderBlockedUsers.includes(recipientId) ||
                          recipientBlockedUsers.includes(senderId);

          const shouldHidePreview = senderIsPrivate || recipientIsPrivate || isBlocked;
          const safeMessageText = shouldHidePreview ? "" : messageText.substring(0, 100);

          // Create notification
          const notification = {
            type: conversationStatus === "pending" ? "message_request" : "message",
            actorId: senderId,
            actorName: senderName,
            conversationId: conversationId,
            messageText: safeMessageText,
            userId: recipientId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          await admin.firestore()
              .collection("users")
              .doc(recipientId)
              .collection("notifications")
              .add(notification);

          console.log(`✅ Message notification created for user ${recipientId}${shouldHidePreview ? " (preview hidden)" : ""}`);

          // Send push notification
          const fcmToken = recipientData?.fcmToken;

          if (fcmToken) {
            const notificationTitle = conversationStatus === "pending" ?
              "New Message Request" :
              isGroup ? groupName || "Group Message" : senderName;

            const notificationBody = conversationStatus === "pending" ?
              `${senderName} wants to message you` :
              shouldHidePreview ? "New message" : messageText.substring(0, 100);

            await admin.messaging().send({
              notification: {
                title: notificationTitle,
                body: notificationBody,
              },
              data: {
                type: conversationStatus === "pending" ? "message_request" : "message",
                actorId: senderId,
                conversationId: conversationId,
              },
              token: fcmToken,
            });

            console.log(`✅ Push notification sent to ${recipientId}${shouldHidePreview ? " (generic message)" : ""}`);
          }
        }

        return {success: true};
      } catch (error) {
        console.error("❌ Error in onMessageSent:", error);
        return null;
      }
    },
);

// ============================================================================
// SCHEDULED: DAILY NOTIFICATION DIGEST PUSH
// Runs at 8:00 AM UTC daily.
// ============================================================================

exports.sendDailyNotificationDigest = onSchedule(
    {schedule: "0 8 * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const db = admin.firestore();
      const today = new Date();
      today.setUTCHours(0, 0, 0, 0);

      console.log("⏰ Running daily notification digest delivery...");

      try {
        const usersSnap = await db.collection("users")
            .where("notificationSettings.digestMode", "==", true)
            .get();

        if (usersSnap.empty) {
          console.log("ℹ️ No users with digest mode enabled");
          return;
        }

        let deliveredCount = 0;

        for (const userDoc of usersSnap.docs) {
          const userId = userDoc.id;
          const userData = userDoc.data();

          const deviceTokensSnap = await db.collection("users")
              .doc(userId)
              .collection("deviceTokens")
              .where("enabled", "==", true)
              .limit(1)
              .get();

          const hasToken = !deviceTokensSnap.empty || !!userData.fcmToken;
          if (!hasToken) continue;

          const unreadSnap = await db.collection("users")
              .doc(userId)
              .collection("notifications")
              .where("read", "==", false)
              .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(today))
              .get();

          if (unreadSnap.empty) continue;

          const typeCounts = {};
          for (const doc of unreadSnap.docs) {
            const t = doc.data().type || "activity";
            typeCounts[t] = (typeCounts[t] || 0) + 1;
          }

          const summaryParts = Object.entries(typeCounts).map(([type, count]) => {
            const label = {
              follow: "new follower",
              amen: "amen",
              comment: "comment",
              reply: "reply",
              mention: "mention",
              repost: "repost",
            }[type] || "notification";
            return `${count} ${label}${count === 1 ? "" : "s"}`;
          });

          const body = summaryParts.slice(0, 3).join(", ") +
              (summaryParts.length > 3 ? ` +${summaryParts.length - 3} more` : "");

          const digestId = `${userId}_${today.getTime()}`;

          const tokens = deviceTokensSnap.empty ?
              (userData.fcmToken ? [userData.fcmToken] : []) :
              deviceTokensSnap.docs.map((d) => d.data().token).filter(Boolean);

          const staleTokens = [];
          await Promise.all(tokens.map(async (token) => {
            try {
              await admin.messaging().send({
                notification: {
                  title: "Your Daily Summary",
                  body,
                },
                data: {
                  type: "digest",
                  digestId,
                  deepLink: `amen://notifications/digest/${digestId}`,
                  unreadCount: String(unreadSnap.size),
                },
                token,
              });
            } catch (err) {
              if (err.code === "messaging/registration-token-not-registered" ||
                  err.code === "messaging/invalid-registration-token") {
                staleTokens.push(token);
              }
            }
          }));

          if (staleTokens.length > 0) {
            const batch = db.batch();
            deviceTokensSnap.docs.forEach((d) => {
              if (staleTokens.includes(d.data().token)) batch.delete(d.ref);
            });
            await batch.commit();
          }

          await db.collection("notificationDigests").doc(digestId).set({
            userId,
            period: "daily",
            itemCount: unreadSnap.size,
            typeCounts,
            delivered: true,
            deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
            opened: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          deliveredCount++;
        }

        console.log(`✅ Digest delivery complete — sent to ${deliveredCount} user(s)`);
      } catch (error) {
        console.error("❌ Error in sendDailyNotificationDigest:", error);
      }
    },
);

// ============================================================================
// BIBLICAL ALIGNMENT FUNCTIONS
// Uses firebase-functions/v2/https (onCall) and firebase-functions/v2/scheduler
// (onSchedule). Exports: checkBiblicalAlignment, suggestBiblicalRewrite,
// saveAICorrection, getDiscernmentPrompt, generateWeeklyAlignmentSummary (scheduled).
// NOTE: attachSharedKnowledgeIntegrity, voteKnowledgeIntegrity,
// getWeeklyAlignmentSummary, updateAlignmentProfile are owned by the creator
// codebase (Backend/functions) and must not be exported here.
// ============================================================================

const biblicalAlignmentFunctions = require("./biblicalAlignmentFunctions");

exports.checkBiblicalAlignment = biblicalAlignmentFunctions.checkBiblicalAlignment;
exports.suggestBiblicalRewrite = biblicalAlignmentFunctions.suggestBiblicalRewrite;
exports.saveAICorrection = biblicalAlignmentFunctions.saveAICorrection;
exports.getDiscernmentPrompt = biblicalAlignmentFunctions.getDiscernmentPrompt;
exports.generateWeeklyAlignmentSummary = biblicalAlignmentFunctions.generateWeeklyAlignmentSummary;

// NOTE: feedContextFunctions (computeFeedContextLabels, attachFeedContextToRankedPosts,
// updateUserContextLabelPreferences, trackContextLabelEvent, suppressContextLabelForUser)
// are owned by the creator codebase (Backend/functions) and must not be exported here.

// ============================================================================
// SMART INBOX DENORMALIZATION
// Uses firebase-functions/v2/firestore (onDocumentCreated). Exports:
// onMessageCreatedForSmartInbox, onMessageCreatedClearsNeedsReply.
// ============================================================================

const smartInboxDenormalization = require("./smartInboxDenormalization");

exports.onMessageCreatedForSmartInbox = smartInboxDenormalization.onMessageCreatedForSmartInbox;
exports.onMessageCreatedClearsNeedsReply = smartInboxDenormalization.onMessageCreatedClearsNeedsReply;

// ============================================================================
// BEREAN v1 — PHASE 2A CORE INTELLIGENCE CALLABLES
// Three callables: bereanChat (main), bereanMemory (summarise), bereanCrisisDetect.
// All require Firebase Auth. Rate-limited via enforceRateLimit.
// Secrets declared via defineSecret — never in responses or logs.
// Added: 2026-06-07
// ============================================================================

const { onCall: onCallV2, HttpsError: HttpsErrorV2 } = require("firebase-functions/v2/https");
const { defineSecret: defineSecretV2 } = require("firebase-functions/params");
const loggerV2 = require("firebase-functions/logger");
const { enforceRateLimit } = require("./rateLimiter");
const { callModel } = require("./router/callModel");

// Secrets required by the Berean callables (resolved by the Firebase runtime)
const BEREAN_ANTHROPIC_KEY = defineSecretV2("ANTHROPIC_API_KEY");
const BEREAN_NVIDIA_KEY    = defineSecretV2("NVIDIA_API_KEY");
const BEREAN_PINECONE_KEY  = defineSecretV2("PINECONE_API_KEY");
const BEREAN_PINECONE_HOST = defineSecretV2("PINECONE_HOST");

// ── Shared auth helper ────────────────────────────────────────────────────────

function requireBereanAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsErrorV2("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

// ── bereanChat ────────────────────────────────────────────────────────────────
// Main Berean callable. Routes through callModel with the task provided by the
// client (mapped from Domain → routing task server-side for security).
// Rate: 30 calls per user per hour.

exports.bereanChat = onCallV2(
  {
    region: "us-central1",
    enforceAppCheck: true,
    timeoutSeconds: 60,
    secrets: [BEREAN_ANTHROPIC_KEY, BEREAN_NVIDIA_KEY, BEREAN_PINECONE_KEY, BEREAN_PINECONE_HOST],
  },
  async (request) => {
    const uid = requireBereanAuth(request);

    const { task, input, memoryContext, safetyLevel } = request.data;

    if (!task || typeof task !== "string") {
      throw new HttpsErrorV2("invalid-argument", "task is required.");
    }
    if (!input || typeof input !== "string") {
      throw new HttpsErrorV2("invalid-argument", "input is required.");
    }
    if (input.length > 4000) {
      throw new HttpsErrorV2("invalid-argument", "input exceeds 4000 character limit.");
    }

    await enforceRateLimit(uid, "bereanChat", 30, 3600);

    loggerV2.info("bereanChat", { uid, task, safetyLevel });

    // Build a memory context string for injection into the system prompt.
    const memoryStr = Array.isArray(memoryContext) && memoryContext.length > 0
      ? `USER MEMORY CONTEXT:\n${memoryContext.map((m) => `[${m.domain}] ${m.summary}`).join("\n")}`
      : "";

    const result = await callModel({
      task,
      input,
      context: memoryStr || undefined,
      userId: uid,
      safetyLevel: safetyLevel ?? "standard",
    });

    if (result.blocked) {
      // Map router block reason to a typed refusal — never throw HttpsError here
      // so the client can display a graceful message rather than a red error.
      return {
        text: null,
        provenance: { sources: [], truthLevel: "refused" },
        refusal: result.reason ?? "moderation_blocked",
        blocked: true,
      };
    }

    if (result.degraded) {
      return {
        text: null,
        provenance: { sources: [], truthLevel: "refused" },
        refusal: "provider_unavailable",
        blocked: false,
      };
    }

    return {
      text: result.output ?? "",
      provenance: { sources: [], truthLevel: "grounded" },
      refusal: null,
      blocked: false,
    };
  },
);

// ── bereanMemory ──────────────────────────────────────────────────────────────
// Memory summarisation callable. Summarises `text` for the given domain using
// Claude (berean_memory_summarize route — fail_closed, output guard).
// Rate: 20 calls per user per hour.

exports.bereanMemory = onCallV2(
  {
    region: "us-central1",
    enforceAppCheck: true,
    timeoutSeconds: 45,
    secrets: [BEREAN_ANTHROPIC_KEY, BEREAN_NVIDIA_KEY],
  },
  async (request) => {
    const uid = requireBereanAuth(request);

    const { domain, text } = request.data;

    if (!domain || typeof domain !== "string") {
      throw new HttpsErrorV2("invalid-argument", "domain is required.");
    }
    if (!text || typeof text !== "string") {
      throw new HttpsErrorV2("invalid-argument", "text is required.");
    }
    if (text.length > 8000) {
      throw new HttpsErrorV2("invalid-argument", "text exceeds 8000 character limit.");
    }

    await enforceRateLimit(uid, "bereanMemory", 20, 3600);

    loggerV2.info("bereanMemory", { uid, domain });

    const result = await callModel({
      task: "berean_memory_summarize",
      input: text,
      userId: uid,
    });

    if (result.blocked || result.degraded) {
      throw new HttpsErrorV2(
        "failed-precondition",
        "Memory summarisation could not complete. Try again.",
      );
    }

    return {
      summary: result.output ?? "",
      domain,
    };
  },
);

// ── bereanCrisisDetect ────────────────────────────────────────────────────────
// Crisis detection callable. Routes through NVIDIA (crisis_handoff route —
// fail_closed). Returns a boolean detection signal ONLY.
//
// HUMAN GATE: Returns detection signal only. AI answer never surfaces to user.
// T&S owns the response queue.
//
// Rate: 60 calls per user per hour (crisis detection must never be rate-blocked).

// Note: Selah corpus + discernment callables are appended at the bottom of this file.

exports.bereanCrisisDetect = onCallV2(
  {
    region: "us-central1",
    enforceAppCheck: true,
    timeoutSeconds: 20,
    secrets: [BEREAN_NVIDIA_KEY],
  },
  async (request) => {
    // HUMAN GATE: Returns detection signal only. AI answer never surfaces to user. T&S owns the response queue.

    const uid = requireBereanAuth(request);

    const { input } = request.data;

    if (!input || typeof input !== "string") {
      throw new HttpsErrorV2("invalid-argument", "input is required.");
    }
    if (input.length > 2000) {
      throw new HttpsErrorV2("invalid-argument", "input exceeds 2000 character limit.");
    }

    await enforceRateLimit(uid, "bereanCrisisDetect", 60, 3600);

    loggerV2.info("bereanCrisisDetect", { uid });

    const result = await callModel({
      task: "crisis_handoff",
      input,
      userId: uid,
      safetyLevel: "crisis",
    });

    // Interpret the NVIDIA guard result as a detection boolean.
    // The router's crisis_handoff route runs NVIDIA NeMo — output is a guard
    // structured result. Treat any block or unsafe signal as detected: true.
    // On degraded / unavailable: default to detected: true (fail-safe).
    let crisisDetected = true;

    if (!result.blocked && !result.degraded && result.output != null) {
      // NVIDIA returns { safe: boolean, categories: string } when dispatched as primary.
      // Output may be a stringified JSON or a plain string.
      if (typeof result.output === "object" && result.output !== null) {
        crisisDetected = result.output.safe === false;
      } else if (typeof result.output === "string") {
        const lower = result.output.toLowerCase();
        crisisDetected = lower.includes("unsafe") || lower.includes("crisis");
      }
    }

    // Return detection signal only — never return AI text content.
    return { crisisDetected };
  },
);

// ============================================================================
// SELAH: PERSONAL CORPUS INDEXING + RETRIEVAL
// Uses firebase-functions/v2/https (onCall). Exports: indexSelahNote, querySelahCorpus.
// Both callables are auth-guarded. Namespace is always `selah-notes-{uid}` (from
// request.auth.uid — never from the client payload). translationRead is explicitly
// rejected at the callable boundary to enforce the open-license invariant.
// Added: 2026-06-07
// ============================================================================

const { indexSelahNote, querySelahCorpus } = require("./selah/selahCorpusService");
exports.indexSelahNote = indexSelahNote;
exports.querySelahCorpus = querySelahCorpus;

// ============================================================================
// SELAH: BEREAN DISCERNMENT ENGINE
// Uses firebase-functions/v2/https (onCall). Exports: runDiscernmentCheck,
// shareDiscernmentCheck.
// Pipeline: NeMo input guard → open-license verse fetch → Claude (discernment
// task, Claude-only, no fallover) → citation validation → NeMo output guard →
// Firestore write (visibility always 'private'; shared only via shareDiscernmentCheck).
// HUMAN GATE: selah.discernmentSharing Remote Config flag must be enabled before
// shareDiscernmentCheck will promote a check to 'shared'.
// Added: 2026-06-07
// ============================================================================

const { runDiscernmentCheck, shareDiscernmentCheck } = require("./selah/discernmentEngine");
exports.runDiscernmentCheck = runDiscernmentCheck;
exports.shareDiscernmentCheck = shareDiscernmentCheck;

// ── bereanBibleLookup ─────────────────────────────────────────────────────────
// Server-side proxy for api.bible lookups.
// BIBLE_API_KEY stays server-side; client never sees the key.
// Supports BSB (bba9f40183526463-01), WEB (9879dbb7cfe39e4d-01), KJV (de4e12af7f28f599-02).
// YouVersion is BLOCKED — any request for provider 'youversion' is rejected.
// Rate: 60 calls per user per hour.

const BEREAN_BIBLE_KEY = defineSecretV2("BIBLE_API_KEY");
const BIBLE_API_BASE   = "https://api.scripture.api.bible/v1";

const BIBLE_IDS = {
  bsb: "bba9f40183526463-01",
  web: "9879dbb7cfe39e4d-01",
  kjv: "de4e12af7f28f599-02",
};

exports.bereanBibleLookup = onCallV2(
  {
    region: "us-central1",
    timeoutSeconds: 15,
    secrets: [BEREAN_BIBLE_KEY],
  },
  async (request) => {
    const uid = requireBereanAuth(request);
    await enforceRateLimit(uid, "bereanBibleLookup", 60, 3600);

    const { reference, translation = "bsb", type = "verse" } = request.data;

    if (!reference || typeof reference !== "string" || reference.length > 200) {
      throw new HttpsErrorV2("invalid-argument", "reference must be a non-empty string under 200 chars.");
    }

    const translationKey = String(translation).toLowerCase();
    if (translationKey === "youversion") {
      // YouVersion BLOCKED — written agreement required before any integration.
      throw new HttpsErrorV2("failed-precondition", "YouVersion integration is not available.");
    }

    const bibleId = BIBLE_IDS[translationKey] ?? BIBLE_IDS.bsb;
    const apiKey  = BIBLE_API_KEY.value() ?? "";
    if (!apiKey) {
      loggerV2.error("bereanBibleLookup: BIBLE_API_KEY not configured");
      throw new HttpsErrorV2("unavailable", "Bible service is not configured. Contact support.");
    }

    const fetch = (await import("node-fetch")).default;

    if (type === "passage") {
      const encoded = encodeURIComponent(reference);
      const url = `${BIBLE_API_BASE}/bibles/${bibleId}/passages/${encoded}?content-type=text&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=true`;
      const res = await fetch(url, { headers: { "api-key": apiKey }, signal: AbortSignal.timeout(10_000) });
      if (!res.ok) {
        const errText = await res.text().catch(() => "");
        loggerV2.error("bereanBibleLookup passage error", { status: res.status, reference });
        throw new HttpsErrorV2("unavailable", `Bible service error ${res.status}`);
      }
      const data = await res.json();
      return { reference, translation: translationKey.toUpperCase(), text: data.data?.content ?? "", bibleId };
    }

    // Single verse lookup
    const encoded = encodeURIComponent(reference);
    const url = `${BIBLE_API_BASE}/bibles/${bibleId}/verses/${encoded}?content-type=text&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=false`;
    const res = await fetch(url, { headers: { "api-key": apiKey }, signal: AbortSignal.timeout(10_000) });
    if (!res.ok) {
      const errText = await res.text().catch(() => "");
      loggerV2.error("bereanBibleLookup verse error", { status: res.status, reference });
      throw new HttpsErrorV2("unavailable", `Bible service error ${res.status}`);
    }
    const data = await res.json();
    return {
      reference:   data.data?.reference ?? reference,
      translation: translationKey.toUpperCase(),
      text:        data.data?.content ?? "",
      bibleId,
    };
  },
);

// ============================================================================
// 242 HUB TRIGGERS — v2 scheduler + Firestore triggers from 242hub.js
// NOTE: reviewCovenantApp and matchKingdomCommerce (onCall) stay in index.js.
// ============================================================================
const hub242Triggers = require("./242hub");
exports.flockIntelligence      = hub242Triggers.flockIntelligence;
exports.processSermonMemory    = hub242Triggers.processSermonMemory;
exports.reviewPrayerSubmission = hub242Triggers.reviewPrayerSubmission;
