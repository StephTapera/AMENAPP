/**
 * src/mediaInteractions/index.js
 *
 * Cloud Function stubs for the 28-feature Media Interactions build.
 * Each function has proper auth checks and signature validation.
 * Implementation bodies are delegated to the per-feature agents (1–7).
 *
 * Exports are registered in functions/index.js via:
 *   const mediaInteractions = require('./src/mediaInteractions');
 *   exports.addReaction      = mediaInteractions.addReaction;
 *   // etc.
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Throws HttpsError if the caller is not authenticated. */
function requireAuth(auth) {
  if (!auth || !auth.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
}

/** Throws HttpsError if any required field is missing from data. */
function requireFields(data, fields) {
  for (const field of fields) {
    if (data[field] == null) {
      throw new HttpsError('invalid-argument', `Missing required field: ${field}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Agent 1 — Reactions
// ---------------------------------------------------------------------------

/**
 * addReaction — Idempotently add or replace a MediaReaction on a media item.
 *
 * Input:  { mediaId: string, type: string, emoji?: string, note?: string, prayerExpiresAt?: ISO8601 }
 * Output: { reactionId: string }
 *
 * Firestore path: /reactions/{reactionId}
 * Indexed by:     mediaId + userId (compound index required)
 */
exports.addReaction = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['mediaId', 'type']);

  const validTypes = ['heart', 'laugh', 'prayer', 'fire', 'cross', 'custom'];
  if (!validTypes.includes(data.type)) {
    throw new HttpsError('invalid-argument', `Invalid reaction type: ${data.type}`);
  }

  // TODO (Agent 1): Implement idempotent upsert, counter increment, prayer timer scheduling.
  throw new HttpsError('unimplemented', 'addReaction not yet implemented — see Agent 1.');
});

/**
 * removeReaction — Delete a reaction the caller owns.
 *
 * Input:  { reactionId: string }
 * Output: { success: boolean }
 */
exports.removeReaction = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['reactionId']);

  // TODO (Agent 1): Verify ownership, delete doc, decrement counter.
  throw new HttpsError('unimplemented', 'removeReaction not yet implemented — see Agent 1.');
});

/**
 * pinReply — Creator pins a single comment reply to the top of a media item.
 *
 * Input:  { mediaId: string, commentId: string }
 * Output: { success: boolean }
 *
 * Only the post author can pin; enforced server-side.
 */
exports.pinReply = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['mediaId', 'commentId']);

  // TODO (Agent 1): Verify caller owns the media, write pinnedReplyId to /mediaSettings/{mediaId}.
  throw new HttpsError('unimplemented', 'pinReply not yet implemented — see Agent 1.');
});

// ---------------------------------------------------------------------------
// Agent 4 — Save & Translate
// ---------------------------------------------------------------------------

/**
 * saveToCollection — Bookmark a media item into a named collection.
 *
 * Input:  { mediaId: string, collectionId?: string, note?: string }
 * Output: { savedItemId: string }
 *
 * Firestore path: /saves/{userId}/items/{saveId}
 */
exports.saveToCollection = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['mediaId']);

  // TODO (Agent 4): Validate mediaId exists, upsert SavedItem, increment MediaCollection.itemCount.
  throw new HttpsError('unimplemented', 'saveToCollection not yet implemented — see Agent 4.');
});

/**
 * translateText — Proxy Claude/OpenAI translation for captions and comments.
 *
 * Input:  { text: string, targetLocale: string }
 * Output: { translatedText: string, sourceLocale: string }
 *
 * Rate-limited to 20 calls/user/day (enforced via /userTranslationUsage/{userId} counters).
 */
exports.translateText = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['text', 'targetLocale']);

  if (!data.text || data.text.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'text must be non-empty.');
  }

  // TODO (Agent 4): Check rate limit, call AI proxy, return translated text.
  throw new HttpsError('unimplemented', 'translateText not yet implemented — see Agent 4.');
});

// ---------------------------------------------------------------------------
// Agent 7 — Faith Layer
// ---------------------------------------------------------------------------

/**
 * attachVerse — Validate a scripture reference against the KJV index and return canonical text.
 *
 * Input:  { reference: string, attachedToId: string, attachedToType: 'reaction'|'comment'|'post' }
 * Output: { attachmentId: string, text: string, translation: 'KJV' }
 *
 * Firestore path: /verseAttachments/{attachmentId}
 */
exports.attachVerse = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['reference', 'attachedToId', 'attachedToType']);

  const validTargets = ['reaction', 'comment', 'post'];
  if (!validTargets.includes(data.attachedToType)) {
    throw new HttpsError('invalid-argument', `Invalid attachedToType: ${data.attachedToType}`);
  }

  // TODO (Agent 7): Look up reference in KJV Firestore index, write VerseAttachment doc.
  throw new HttpsError('unimplemented', 'attachVerse not yet implemented — see Agent 7.');
});
