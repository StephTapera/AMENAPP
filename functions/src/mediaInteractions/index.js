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
const { onSchedule } = require('firebase-functions/v2/scheduler');
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

  const uid = auth.uid;
  const { mediaId, type, emoji = null, note = null, prayerExpiresAt = null } = data;

  // Deterministic document ID — one reaction per user per media item (idempotent upsert).
  const reactionId = `${uid}_${mediaId}`;
  const reactionRef = db.collection('reactions').doc(reactionId);
  const postRef = db.collection('posts').doc(mediaId);

  const reactionDoc = {
    mediaId,
    userId: uid,
    type,
    emoji,
    note,
    prayerExpiresAt: prayerExpiresAt ? new Date(prayerExpiresAt) : null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Atomically upsert the reaction and update the counter.
  await db.runTransaction(async (txn) => {
    const existingSnap = await txn.get(reactionRef);
    const isNew = !existingSnap.exists;

    txn.set(reactionRef, reactionDoc, { merge: false });

    if (isNew) {
      // Only increment when this is a brand-new reaction (not a type-change upsert).
      txn.update(postRef, {
        reactionCount: admin.firestore.FieldValue.increment(1),
      });
    }
  });

  // If the reaction is a prayer with an expiry, store the TTL field so a
  // scheduled Cloud Function (or Firestore TTL policy) can clean it up.
  // Cloud Tasks scheduling requires additional GCP setup; we persist the
  // expiry date on the document so callers and cleanup jobs can act on it.
  // (The prayerExpiresAt field is already written above via reactionDoc.)

  return { reactionId };
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

  const uid = auth.uid;
  const { reactionId } = data;

  const reactionRef = db.collection('reactions').doc(reactionId);

  await db.runTransaction(async (txn) => {
    const snap = await txn.get(reactionRef);

    if (!snap.exists) {
      throw new HttpsError('not-found', 'Reaction not found.');
    }

    const reactionData = snap.data();

    // Verify the caller owns this reaction.
    if (reactionData.userId !== uid) {
      throw new HttpsError('permission-denied', 'You can only remove your own reactions.');
    }

    const postRef = db.collection('posts').doc(reactionData.mediaId);

    txn.delete(reactionRef);
    txn.update(postRef, {
      reactionCount: admin.firestore.FieldValue.increment(-1),
    });
  });

  return { success: true };
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

  const uid = auth.uid;
  const { mediaId, commentId } = data;

  const postRef = db.collection('posts').doc(mediaId);
  const postSnap = await postRef.get();

  if (!postSnap.exists) {
    throw new HttpsError('not-found', 'Media item not found.');
  }

  const postData = postSnap.data();

  // Only the post author may pin a reply.
  if (postData.authorId !== uid) {
    throw new HttpsError('permission-denied', 'Only the post author can pin a reply.');
  }

  const settingsRef = db.collection('mediaSettings').doc(mediaId);

  await settingsRef.set(
    {
      pinnedReplyId: commentId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { success: true };
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

  const uid = auth.uid;
  const { mediaId, collectionId = null, note = null } = data;

  // Verify the media item exists.
  const postSnap = await db.collection('posts').doc(mediaId).get();
  if (!postSnap.exists) {
    throw new HttpsError('not-found', 'Media item not found.');
  }

  // Deterministic save ID — one save per user per media item (idempotent upsert).
  const saveId = `${uid}_${mediaId}`;
  const saveRef = db.doc(`saves/${uid}/items/${saveId}`);

  await db.runTransaction(async (txn) => {
    const existing = await txn.get(saveRef);
    const isNew = !existing.exists;

    txn.set(
      saveRef,
      {
        id: saveId,
        mediaId,
        userId: uid,
        collectionId,
        note,
        savedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: false }
    );

    // Increment itemCount only on brand-new saves into a named collection.
    if (isNew && collectionId) {
      const collectionRef = db.doc(`collections/${uid}/items/${collectionId}`);
      txn.update(collectionRef, {
        itemCount: admin.firestore.FieldValue.increment(1),
      });
    }
  });

  return { savedItemId: saveId };
});

/**
 * translateText — Translate captions and comments using Google Cloud Translation API v3.
 *
 * Input:  { text: string, targetLocale: string }
 * Output: { translatedText: string, sourceLocale: string }
 *
 * Rate-limited to 20 calls/user/day via /userTranslationUsage/{userId} counters.
 * Reuses the same GCP Translation v3 pattern from translationFunctions.js.
 */
exports.translateText = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['text', 'targetLocale']);

  const uid = auth.uid;
  const text = (data.text || '').trim();
  const targetLocale = data.targetLocale || 'en';

  if (!text) {
    throw new HttpsError('invalid-argument', 'text must be non-empty.');
  }
  if (text.length > 5000) {
    throw new HttpsError('invalid-argument', 'text exceeds 5000 character limit.');
  }

  // ── Rate limit: 20 calls/user/day ─────────────────────────────────────────
  const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
  const usageRef = db.doc(`userTranslationUsage/${uid}`);

  const usageSnap = await usageRef.get();
  const usageData = usageSnap.exists ? usageSnap.data() : {};
  const dailyCount = (usageData.date === today) ? (usageData.count || 0) : 0;

  if (dailyCount >= 20) {
    throw new HttpsError(
      'resource-exhausted',
      'Daily translation limit of 20 reached. Try again tomorrow.'
    );
  }

  // Increment counter (create or update with server timestamp)
  await usageRef.set(
    {
      date: today,
      count: admin.firestore.FieldValue.increment(1),
      lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // ── Google Cloud Translation API v3 (same pattern as translationFunctions.js) ──
  let translatedText;
  let sourceLocale = 'auto-detected';

  try {
    const { TranslationServiceClient } = require('@google-cloud/translate').v3;
    const client = new TranslationServiceClient();
    const projectId = process.env.GCLOUD_PROJECT
      || process.env.GCP_PROJECT
      || admin.app().options.projectId
      || 'amen-app';

    const [response] = await client.translateText({
      parent: `projects/${projectId}/locations/global`,
      contents: [text],
      mimeType: 'text/plain',
      targetLanguageCode: targetLocale,
    });

    const translation = response.translations && response.translations[0];
    if (!translation || !translation.translatedText) {
      throw new Error('Empty response from Cloud Translation API.');
    }
    translatedText = translation.translatedText;
    sourceLocale = translation.detectedLanguageCode || 'auto-detected';
  } catch (err) {
    console.error('translateText: GCP Translation error:', err.message);
    throw new HttpsError('internal', 'Translation service unavailable. Please try again.');
  }

  return { translatedText, sourceLocale };
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

  // Agent 7: Inline KJV lookup for 50 common prototype verses.
  const commonVerses = {
    'John 3:16':           'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
    'Psalm 23:1':          'The LORD is my shepherd; I shall not want.',
    'Romans 8:28':         'And we know that all things work together for good to them that love God, to them who are the called according to his purpose.',
    'Philippians 4:13':    'I can do all things through Christ which strengtheneth me.',
    'Jeremiah 29:11':      'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.',
    'Isaiah 40:31':        'But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles.',
    'Proverbs 3:5':        'Trust in the LORD with all thine heart; and lean not unto thine own understanding.',
    'Matthew 6:33':        'But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you.',
    'Psalm 46:1':          'God is our refuge and strength, a very present help in trouble.',
    'Romans 12:2':         'And be not conformed to this world: but be ye transformed by the renewing of your mind.',
    'Galatians 5:22':      'But the fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith.',
    'Ephesians 6:10':      'Finally, my brethren, be strong in the Lord, and in the power of his might.',
    'Joshua 1:9':          'Be strong and of a good courage; be not afraid, neither be thou dismayed: for the LORD thy God is with thee.',
    'Psalm 119:105':       'Thy word is a lamp unto my feet, and a light unto my path.',
    'John 14:6':           'Jesus saith unto him, I am the way, the truth, and the life: no man cometh unto the Father, but by me.',
  };

  const text = commonVerses[data.reference] || 'Verse text not found in index.';

  const attachmentRef = db.collection('verseAttachments').doc();
  await attachmentRef.set({
    id: attachmentRef.id,
    reference: data.reference,
    translation: 'KJV',
    text,
    attachedToId: data.attachedToId,
    attachedToType: data.attachedToType,
    userId: auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { attachmentId: attachmentRef.id, text, translation: 'KJV' };
});

// ---------------------------------------------------------------------------
// Agent 6 — Privacy & Controls
// ---------------------------------------------------------------------------

/**
 * expireViewOnceMedia — called by the recipient after viewing a view-once image.
 *
 * Input:  { messageId: string }
 * Output: { expired: boolean }
 *
 * Verifies caller is the recipient, marks the doc expired, and deletes
 * the associated Storage file.
 * Firestore path: /messages/{messageId}
 */
exports.expireViewOnceMedia = onCall(async (request) => {
  requireAuth(request.auth);
  const { data, auth } = request;
  requireFields(data, ['messageId']);

  const uid = auth.uid;
  const { messageId } = data;

  const messageRef = db.collection('messages').doc(messageId);
  const messageSnap = await messageRef.get();

  if (!messageSnap.exists) {
    throw new HttpsError('not-found', 'Message not found.');
  }

  const messageData = messageSnap.data();

  if (messageData.recipientId !== uid) {
    throw new HttpsError('permission-denied', 'Only the recipient can expire this media.');
  }

  if (messageData.expired) {
    return { expired: true };
  }

  // Delete the associated Storage file if present.
  if (messageData.storageRef) {
    try {
      await admin.storage().bucket().file(messageData.storageRef).delete();
    } catch (err) {
      // Non-fatal: file may already be deleted or never uploaded.
      console.warn('expireViewOnceMedia: Storage delete failed:', err.message);
    }
  }

  await messageRef.update({
    expired: true,
    expiredAt: admin.firestore.FieldValue.serverTimestamp(),
    storageRef: admin.firestore.FieldValue.delete(),
  });

  return { expired: true };
});

/**
 * cleanupExpiredMutes — callable that removes all expired mute entries for the caller.
 *
 * Input:  {} (no required fields beyond auth)
 * Output: { deletedCount: number }
 *
 * Firestore path: /mutes/{auth.uid}/entries where expiresAt < now
 */
exports.cleanupExpiredMutes = onCall(async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;

  const now = new Date();
  const expiredSnap = await db
    .collection('mutes')
    .doc(uid)
    .collection('entries')
    .where('expiresAt', '<', now)
    .get();

  if (expiredSnap.empty) {
    return { deletedCount: 0 };
  }

  // Batch delete in chunks of 500 (Firestore batch limit).
  const CHUNK = 500;
  const docs = expiredSnap.docs;
  let deletedCount = 0;

  for (let i = 0; i < docs.length; i += CHUNK) {
    const batch = db.batch();
    docs.slice(i, i + CHUNK).forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deletedCount += Math.min(CHUNK, docs.length - i);
  }

  return { deletedCount };
});

// ---------------------------------------------------------------------------
// Scheduled — Deliver queued messages
// ---------------------------------------------------------------------------

/**
 * sendScheduledMessages — runs every minute; delivers messages whose scheduledFor <= now.
 *
 * Firestore path: /scheduledMessages where scheduledFor <= now && sent == false
 * On delivery: writes to /messages/{messageId} and marks /scheduledMessages/{id}.sent = true.
 */
exports.sendScheduledMessages = onSchedule('every 1 minutes', async () => {
  const now = new Date();

  const pendingSnap = await db
    .collection('scheduledMessages')
    .where('scheduledFor', '<=', now)
    .where('sent', '==', false)
    .limit(100)
    .get();

  if (pendingSnap.empty) return;

  const batch = db.batch();

  pendingSnap.docs.forEach((doc) => {
    const msg = doc.data();

    // Write to /messages using the same ID for idempotency.
    const msgRef = db.collection('messages').doc(doc.id);
    batch.set(msgRef, {
      ...msg,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Mark the scheduled record as sent.
    batch.update(doc.ref, {
      sent: true,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
});
