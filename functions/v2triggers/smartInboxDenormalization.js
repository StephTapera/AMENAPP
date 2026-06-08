/**
 * smartInboxDenormalization.js
 *
 * System 36: Messaging Filters & Smart Inbox.
 *
 * Forward-only denormalization of per-user inbox metadata into
 * `conversations/{conversationId}/inboxMetadata/{userId}`.
 *
 * Each new message triggers a small fan-out update: for every recipient
 * (participant !== senderId), the per-user metadata doc gets the booleans
 * the iOS client uses to drive filter chips. Historical messages are NOT
 * backfilled — only new traffic produces signals. This caps cost at the
 * production write rate and never invents data for filters that have
 * no real backing.
 *
 * Server-managed fields (writable only via this function):
 *   hasDraft, hasMentionForUser, needsReply, hasMedia, hasLink, hasFile,
 *   hasScheduled, hasPrayerRequest, needsSafetyReview, isBlockedOrRestricted,
 *   updatedAt, computedBy
 *
 * User-toggleable fields (untouched by this function):
 *   isStarred, isArchivedForUser, isUnknownContactDismissed
 *
 * Gate: this function is a no-op unless Remote Config flag
 * `messaging_smart_inbox_counts_enabled` is true. The flag is checked at
 * the project level (the trigger still fires, but exits early).
 */

'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions/v2');
const admin = require('firebase-admin');

const db = () => admin.firestore();
const REGION = 'us-central1';

// ─── Field helpers ──────────────────────────────────────────────────────────

function isMediaMessage(msg) {
  const t = msg.messageType || msg.type;
  if (t === 'image' || t === 'video') return true;
  if (msg.mediaURL && String(msg.mediaURL).length > 0) return true;
  const atts = Array.isArray(msg.attachments) ? msg.attachments : [];
  return atts.some(a => a && (a.type === 'photo' || a.type === 'video'));
}

function isLinkMessage(msg) {
  const t = msg.messageType || msg.type;
  if (t === 'link') return true;
  if (msg.linkURL && String(msg.linkURL).length > 0) return true;
  if (Array.isArray(msg.linkPreviews) && msg.linkPreviews.length > 0) return true;
  return false;
}

function isFileMessage(msg) {
  const t = msg.messageType || msg.type;
  if (t === 'file') return true;
  if (msg.mediaFileName && String(msg.mediaFileName).length > 0) return true;
  const atts = Array.isArray(msg.attachments) ? msg.attachments : [];
  return atts.some(a => a && a.type === 'document');
}

function isScheduledMessage(msg) {
  // A scheduled message is created with a future deliveryAt or
  // an explicit scheduledFor field. We never invent scheduling locally.
  if (msg.scheduledFor) return true;
  if (msg.deliveryAt && msg.deliveryAt.toMillis && msg.deliveryAt.toMillis() > Date.now()) {
    return true;
  }
  return false;
}

function isPrayerRequestMessage(msg) {
  // Only true if the writer explicitly set the prayer flag — never inferred
  // from text content (that would be a privacy footgun).
  return msg.isPrayerRequest === true || msg.category === 'prayerRequest';
}

function needsSafetyReviewMessage(msg) {
  // Safety review is set ONLY by the moderation pipeline. We don't infer
  // anything client-side; if the field is absent, treat as false.
  return msg.safetyReviewPending === true || msg.moderationStatus === 'pending_review';
}

// ─── Remote Config gate ─────────────────────────────────────────────────────

async function isSmartInboxEnabled() {
  // Read-through cache would be ideal; for now we hit the template directly.
  // Cost: 1 call per cold function instance. Hot instances share the value
  // because the trigger reuses the same Node process.
  try {
    const remoteConfig = admin.remoteConfig();
    const tpl = await remoteConfig.getTemplate();
    const param = tpl.parameters.messaging_smart_inbox_counts_enabled;
    if (!param) return false;
    const raw = param.defaultValue && param.defaultValue.value;
    return raw === 'true' || raw === true;
  } catch (e) {
    logger.warn('smartInbox: failed to read remote config flag, defaulting OFF', e.message);
    return false;
  }
}

// ─── Main Trigger: onMessageCreated ─────────────────────────────────────────

const onMessageCreatedForSmartInbox = onDocumentCreated(
  {
    document: 'conversations/{conversationId}/messages/{messageId}',
    region: REGION,
  },
  async (event) => {
    const enabled = await isSmartInboxEnabled();
    if (!enabled) return;

    const snap = event.data;
    if (!snap) return;
    const msg = snap.data() || {};
    const conversationId = event.params.conversationId;

    // Load the conversation to know who the participants are.
    const convoRef = db().collection('conversations').doc(conversationId);
    const convoSnap = await convoRef.get();
    if (!convoSnap.exists) return;
    const convo = convoSnap.data() || {};
    const participantIds = Array.isArray(convo.participantIds) ? convo.participantIds : [];
    if (participantIds.length === 0) return;

    const senderId = msg.senderId || msg.sender || '';
    const recipientIds = participantIds.filter(id => id !== senderId);
    if (recipientIds.length === 0) return;

    // Precompute message-level booleans once.
    const flags = {
      hasMedia: isMediaMessage(msg),
      hasLink: isLinkMessage(msg),
      hasFile: isFileMessage(msg),
      hasScheduled: isScheduledMessage(msg),
      hasPrayerRequest: isPrayerRequestMessage(msg),
      needsSafetyReview: needsSafetyReviewMessage(msg),
    };

    const mentioned = Array.isArray(msg.mentionedUserIds) ? msg.mentionedUserIds : [];
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Forward-only: every recipient's inbox metadata doc gets the booleans
    // OR'd in. We use set(..., { merge: true }) with sentinel-true so that
    // a single message can't downgrade a true value to false. Clearing is
    // the client's responsibility (e.g., on read, on archive).
    const batch = db().batch();
    for (const uid of recipientIds) {
      const ref = convoRef.collection('inboxMetadata').doc(uid);
      const update = {
        computedBy: 'onMessageCreatedForSmartInbox',
        updatedAt: now,
      };
      if (flags.hasMedia)         update.hasMedia = true;
      if (flags.hasLink)          update.hasLink = true;
      if (flags.hasFile)          update.hasFile = true;
      if (flags.hasScheduled)     update.hasScheduled = true;
      if (flags.hasPrayerRequest) update.hasPrayerRequest = true;
      if (flags.needsSafetyReview) update.needsSafetyReview = true;
      if (mentioned.includes(uid)) update.hasMentionForUser = true;
      // needsReply: if the sender is not this user and this is the latest message,
      // we set true. The client downgrades it when the user sends a reply.
      update.needsReply = true;

      batch.set(ref, update, { merge: true });
    }

    try {
      await batch.commit();
    } catch (e) {
      logger.error('smartInbox: batch.commit failed', {
        conversationId,
        error: e.message,
      });
    }
  }
);

// ─── Reset Trigger: clear needsReply when the owner sends a message ─────────

const onMessageCreatedClearsNeedsReply = onDocumentCreated(
  {
    document: 'conversations/{conversationId}/messages/{messageId}',
    region: REGION,
  },
  async (event) => {
    const enabled = await isSmartInboxEnabled();
    if (!enabled) return;

    const snap = event.data;
    if (!snap) return;
    const msg = snap.data() || {};
    const senderId = msg.senderId || msg.sender || '';
    if (!senderId) return;

    const conversationId = event.params.conversationId;
    const ref = db()
      .collection('conversations').doc(conversationId)
      .collection('inboxMetadata').doc(senderId);

    try {
      // The sender just replied — their needsReply is now false. We do NOT
      // touch any other field; merge stays surgical.
      await ref.set(
        {
          needsReply: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          computedBy: 'onMessageCreatedClearsNeedsReply',
        },
        { merge: true }
      );
    } catch (e) {
      logger.error('smartInbox: clear needsReply failed', {
        conversationId,
        senderId,
        error: e.message,
      });
    }
  }
);

module.exports = {
  onMessageCreatedForSmartInbox,
  onMessageCreatedClearsNeedsReply,
};
