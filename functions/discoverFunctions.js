'use strict';

/**
 * discoverFunctions.js
 *
 * Cloud Functions for the Discover / Featured carousel feature.
 *
 * setFeatured          — admin-only callable to create/update a featured card.
 *                        Sets moderationCleared = false; GUARDIAN must clear it
 *                        before the card surfaces in the iOS client query.
 * clearFeaturedModeration — admin-only callable to approve a card post-GUARDIAN review.
 * markEngaged          — user callable; upserts an entry in users/{uid}/continue.
 *                        Called by the iOS client when the user opens or plays content.
 * deleteContinueRow    — user callable; removes one entry from users/{uid}/continue.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const db     = admin.firestore();
const REGION = 'us-central1';

// ─── setFeatured ─────────────────────────────────────────────────────────────

exports.setFeatured = onCall({ region: REGION }, async (req) => {
  if (!req.auth?.token?.admin) {
    throw new HttpsError('permission-denied', 'Admin credential required');
  }
  const { id, title, subtitle, badgeLabel, accentHex, imageURL,
          rating, contentRef, order, active } = req.data;

  if (!title) throw new HttpsError('invalid-argument', 'title is required');

  const payload = {
    title,
    subtitle:          subtitle   ?? null,
    badgeLabel:        badgeLabel ?? null,
    accentHex:         accentHex  ?? null,
    imageURL:          imageURL   ?? null,
    rating:            rating     ?? null,
    contentRef:        contentRef ?? null,
    order:             typeof order  === 'number' ? order  : 0,
    active:            typeof active === 'boolean' ? active : true,
    moderationCleared: false,  // GUARDIAN clears this; never trust client
    updatedAt:         admin.firestore.FieldValue.serverTimestamp(),
  };

  const ref = id
    ? db.collection('featured').doc(id)
    : db.collection('featured').doc();

  await ref.set(payload, { merge: true });
  console.log(`[discover] setFeatured id=${ref.id} by admin=${req.auth.uid}`);
  return { id: ref.id };
});

// ─── clearFeaturedModeration ─────────────────────────────────────────────────

exports.clearFeaturedModeration = onCall({ region: REGION }, async (req) => {
  if (!req.auth?.token?.admin) {
    throw new HttpsError('permission-denied', 'Admin credential required');
  }
  const { id } = req.data;
  if (!id) throw new HttpsError('invalid-argument', 'id is required');

  await db.collection('featured').doc(id).update({
    moderationCleared: true,
    clearedAt:         admin.firestore.FieldValue.serverTimestamp(),
    clearedBy:         req.auth.uid,
  });
  console.log(`[discover] clearFeaturedModeration id=${id} by admin=${req.auth.uid}`);
  return { ok: true };
});

// ─── markEngaged ─────────────────────────────────────────────────────────────
// Called by iOS when a user opens/plays any content item.
// Payload: { kind, refID, title, accentHex?, imageURL? }

exports.markEngaged = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Must be signed in');

  const { kind, refID, title, accentHex, imageURL } = req.data;
  if (!kind || !refID) {
    throw new HttpsError('invalid-argument', 'kind and refID are required');
  }

  const validKinds = ['post', 'ariseVideo', 'outpourClip', 'study', 'verse', 'churchNote'];
  if (!validKinds.includes(kind)) {
    throw new HttpsError('invalid-argument', `kind must be one of: ${validKinds.join(', ')}`);
  }

  const docId = `${kind}_${refID}`;
  await db.collection('users').doc(uid).collection('continue').doc(docId).set({
    contentRef:     { kind, refID },
    title:          title      ?? '',
    accentHex:      accentHex  ?? null,
    imageURL:       imageURL   ?? null,
    lastEngagedAt:  admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true };
});

// ─── deleteContinueRow ───────────────────────────────────────────────────────
// User removes a single "Continue in AMEN" entry themselves.
// Payload: { entryId }

exports.deleteContinueRow = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Must be signed in');

  const { entryId } = req.data;
  if (!entryId) throw new HttpsError('invalid-argument', 'entryId is required');

  await db.collection('users').doc(uid).collection('continue').doc(entryId).delete();
  return { ok: true };
});
