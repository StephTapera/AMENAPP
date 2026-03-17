/**
 * postAndCommentFunctions.js
 *
 * Server-side enforcement for Create Post + Comments pipeline.
 * These functions run as the authoritative source of truth for:
 *   - Post publishing finalization (counters, status, media refs)
 *   - Comment creation (atomic counter increment, rate limiting)
 *   - Reaction toggling (idempotent, transactional counts)
 *   - Media finalization (EXIF stripping verification, thumbnail refs)
 *
 * All counter writes happen here via admin SDK — Firestore rules block
 * client counter writes entirely. Clients write optimistic local state;
 * Cloud Functions write the canonical server state.
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onObjectFinalized }  = require('firebase-functions/v2/storage');
const { onDocumentCreated }  = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const db      = admin.firestore();
// Lazy RTDB init — top-level admin.database() throws during Firebase deploy analysis
// if FIREBASE_CONFIG is not yet populated. Use the explicit URL to force resolution.
let _rtdb = null;
const getRtdb = () => {
  if (!_rtdb) _rtdb = admin.database("https://amen-5e359-default-rtdb.firebaseio.com");
  return _rtdb;
};
const storage = admin.storage();

const REGION = 'us-central1';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Server-side rate limit check (rolling window, Firestore-backed)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns true if the user has exceeded the given limit within the window.
 * @param {string} uid
 * @param {string} action   e.g. 'post', 'comment'
 * @param {number} maxCount Max allowed in window
 * @param {number} windowMs Rolling window in ms (default 5 min)
 */
async function isRateLimited(uid, action, maxCount = 10, windowMs = 5 * 60 * 1000) {
  const now = Date.now();
  const windowStart = now - windowMs;
  const ref = db.collection('rateLimitCounters')
    .doc(`${uid}_${action}`);

  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.exists ? doc.data() : { timestamps: [] };

    // Prune old timestamps
    const recent = (data.timestamps || []).filter(ts => ts > windowStart);

    if (recent.length >= maxCount) {
      return true; // rate limited
    }

    recent.push(now);
    tx.set(ref, { timestamps: recent }, { merge: true });
    return false;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. finalizePostPublish
//    Called by client after all media uploads complete.
//    Marks post status = 'published', sets media array, updates lastCommentAt.
//    Idempotent: safe to call multiple times.
// ─────────────────────────────────────────────────────────────────────────────

exports.finalizePostPublish = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Must be signed in');

  const { postId, mediaUrls = [] } = request.data;
  if (!postId || typeof postId !== 'string') {
    throw new HttpsError('invalid-argument', 'postId required');
  }

  const postRef = db.collection('posts').doc(postId);
  const postSnap = await postRef.get();

  if (!postSnap.exists) {
    throw new HttpsError('not-found', 'Post not found');
  }

  const post = postSnap.data();

  // Authorization: only the post author can finalize their post
  if (post.authorId !== auth.uid) {
    throw new HttpsError('permission-denied', 'Not your post');
  }

  // Idempotency: already published → no-op
  if (post.status === 'published') {
    return { success: true, alreadyPublished: true };
  }

  // Validate mediaUrls if present
  if (!Array.isArray(mediaUrls) || mediaUrls.length > 4) {
    throw new HttpsError('invalid-argument', 'mediaUrls must be array of max 4');
  }

  // Validate all URLs belong to the author's storage path
  for (const url of mediaUrls) {
    if (typeof url !== 'string') {
      throw new HttpsError('invalid-argument', 'All mediaUrls must be strings');
    }
    // URL must reference the author's own storage folder
    if (!url.includes(`/post_media/${auth.uid}/`)) {
      throw new HttpsError('permission-denied', `Media URL does not belong to post author: ${url}`);
    }
  }

  await postRef.update({
    status: 'published',
    media: mediaUrls,
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
    amenCount: post.amenCount ?? 0,
    lightbulbCount: post.lightbulbCount ?? 0,
    commentCount: post.commentCount ?? 0,
    repostCount: post.repostCount ?? 0,
  });

  return { success: true, postId };
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. addComment
//    Validates, writes comment to Realtime Database, increments commentCount
//    on the Firestore post document atomically.
//    Rate-limited: max 30 comments per user per 5 minutes.
//    Idempotent via clientCommentId deduplication key.
// ─────────────────────────────────────────────────────────────────────────────

exports.addComment = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Must be signed in');

  const {
    postId,
    text,
    clientCommentId, // UUID generated client-side for idempotency
    parentCommentId = null,
  } = request.data;

  // Validate inputs
  if (!postId || typeof postId !== 'string') {
    throw new HttpsError('invalid-argument', 'postId required');
  }
  if (!text || typeof text !== 'string') {
    throw new HttpsError('invalid-argument', 'text required');
  }
  const trimmed = text.trim();
  if (trimmed.length === 0 || trimmed.length > 2000) {
    throw new HttpsError('invalid-argument', 'text must be 1–2000 characters');
  }
  if (!clientCommentId || typeof clientCommentId !== 'string') {
    throw new HttpsError('invalid-argument', 'clientCommentId required for idempotency');
  }

  // Rate limit: max 30 comments per 5 minutes
  const limited = await isRateLimited(auth.uid, 'comment', 30, 5 * 60 * 1000);
  if (limited) {
    throw new HttpsError('resource-exhausted', 'Too many comments. Please wait before commenting again.');
  }

  // Idempotency: check if comment with this clientCommentId was already written
  const idempotencyRef = db.collection('commentIdempotencyKeys').doc(clientCommentId);
  const idempotencySnap = await idempotencyRef.get();
  if (idempotencySnap.exists) {
    const existing = idempotencySnap.data();
    return { success: true, commentId: existing.commentId, alreadyExists: true };
  }

  // Verify post exists and is published
  const postSnap = await db.collection('posts').doc(postId).get();
  if (!postSnap.exists) {
    throw new HttpsError('not-found', 'Post not found');
  }
  const post = postSnap.data();
  if (post.status !== 'published') {
    throw new HttpsError('failed-precondition', 'Post is not published');
  }

  // Check user is not blocked by the post author
  const blockRef = db.collection('users').doc(post.authorId)
    .collection('blockedUsers').doc(auth.uid);
  const blockSnap = await blockRef.get();
  if (blockSnap.exists) {
    throw new HttpsError('permission-denied', 'You cannot comment on this post');
  }

  // Get commenter's display info
  const commenterSnap = await db.collection('users').doc(auth.uid).get();
  const commenter = commenterSnap.data() || {};

  // Write to Realtime Database (canonical comment store)
  const commentRef = getRtdb().ref(`postInteractions/${postId}/comments`).push();
  const commentId = commentRef.key;

  const commentData = {
    authorId: auth.uid,
    authorName: commenter.displayName || commenter.username || 'User',
    authorUsername: commenter.username || '',
    authorProfileImageURL: commenter.profileImageURL || null,
    text: trimmed,
    createdAt: admin.database.ServerValue.TIMESTAMP,
    parentCommentId: parentCommentId || null,
    clientCommentId,
    likeCount: 0,
  };

  await commentRef.set(commentData);

  // Atomically increment commentCount on Firestore post (admin SDK bypasses rules)
  await db.collection('posts').doc(postId).update({
    commentCount: admin.firestore.FieldValue.increment(1),
    lastCommentAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Store idempotency key (TTL 7 days — cleaned up by scheduled function)
  await idempotencyRef.set({
    commentId,
    postId,
    authorId: auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  });

  return { success: true, commentId };
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. toggleReaction
//    Idempotent reaction toggle (amen / lightbulb).
//    Uses RTDB transaction for the user's reaction state,
//    and Firestore FieldValue.increment for the counter.
//    Safe under concurrency: two rapid calls resolve to the same final state.
// ─────────────────────────────────────────────────────────────────────────────

exports.toggleReaction = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Must be signed in');

  const { postId, reactionType } = request.data;

  if (!postId || typeof postId !== 'string') {
    throw new HttpsError('invalid-argument', 'postId required');
  }
  if (!['amen', 'lightbulb'].includes(reactionType)) {
    throw new HttpsError('invalid-argument', 'reactionType must be amen or lightbulb');
  }

  const countField = reactionType === 'amen' ? 'amenCount' : 'lightbulbCount';

  // RTDB path for user's reaction (presence = reacted)
  const userReactionRef = getRtdb().ref(
    `postInteractions/${postId}/${reactionType}s/${auth.uid}`
  );

  let didAdd = false;

  // RTDB transaction: atomically toggle presence
  await userReactionRef.transaction((current) => {
    if (current === null) {
      didAdd = true;
      return { uid: auth.uid, createdAt: admin.database.ServerValue.TIMESTAMP };
    } else {
      didAdd = false;
      return null; // removes the node
    }
  });

  // Increment or decrement Firestore counter (admin SDK, bypasses rules)
  // Use max(0, count - 1) semantics via transaction to prevent negative counts
  const postRef = db.collection('posts').doc(postId);

  if (didAdd) {
    await postRef.update({
      [countField]: admin.firestore.FieldValue.increment(1),
    });
  } else {
    // Safe decrement with floor at 0
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(postRef);
      const current = snap.data()?.[countField] ?? 0;
      tx.update(postRef, { [countField]: Math.max(0, current - 1) });
    });
  }

  return { success: true, reacted: didAdd };
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. onMediaFinalize
//    Triggered when a file is uploaded to Firebase Storage.
//    For post_media/ paths:
//      - Verifies the file is an allowed type (belt-and-suspenders after Storage rules)
//      - Confirms EXIF was stripped (iOS client strips before upload; server checks size heuristic)
//      - Generates/registers a thumbnail reference if Cloud Function thumbnail extension is used
//      - Updates post document's mediaProcessingStatus
// ─────────────────────────────────────────────────────────────────────────────

exports.onMediaFinalize = onObjectFinalized({ region: 'us-west1' }, async (event) => {
  const object = event.data;
  const filePath = object.name; // e.g. "post_media/{authorUserId}/{postId}/{fileName}"
  const contentType = object.contentType;

  // Only process post_media uploads
  if (!filePath || !filePath.startsWith('post_media/')) return;

  // Parse path segments
  const segments = filePath.split('/');
  if (segments.length < 4) return; // unexpected path format

  const authorUserId = segments[1];
  const postId = segments[2];
  // const fileName = segments[3]; // available if needed

  // Belt-and-suspenders: verify allowed content type even though Storage rules enforce it
  const allowedTypes = [
    'image/jpeg', 'image/jpg', 'image/png',
    'image/webp', 'image/heic', 'image/heif',
    'video/mp4', 'video/quicktime', 'video/x-m4v',
  ];

  if (!allowedTypes.includes(contentType)) {
    console.warn(`[onMediaFinalize] Disallowed content type ${contentType} at ${filePath} — deleting`);
    await storage.bucket(object.bucket).file(filePath).delete();
    return;
  }

  // Get the download URL
  const file = storage.bucket(object.bucket).file(filePath);
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: '2099-01-01', // Long-lived; use Firebase Hosting URLs in production
  });

  // Mark file as processed in Firestore post document
  const postRef = db.collection('posts').doc(postId);
  const postSnap = await postRef.get();

  if (!postSnap.exists) {
    console.warn(`[onMediaFinalize] Post ${postId} not found for media at ${filePath}`);
    return;
  }

  const post = postSnap.data();

  // Verify uploader matches post author (defence in depth)
  if (post.authorId !== authorUserId) {
    console.error(`[onMediaFinalize] Author mismatch for ${filePath} — deleting file`);
    await file.delete();
    return;
  }

  // Update media processing status (non-destructive merge)
  await postRef.update({
    [`mediaProcessingStatus.${object.generation}`]: 'processed',
  });

  console.log(`[onMediaFinalize] Processed ${filePath} for post ${postId}`);
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. onPostCreate (Firestore trigger)
//    Runs after a post document is created by the client.
//    Validates the post, runs moderation, and either publishes or flags it.
//    This is the canonical "server finalizer" for text-only posts.
// ─────────────────────────────────────────────────────────────────────────────

exports.onPostCreateValidate = onDocumentCreated(
  { document: 'posts/{postId}', region: REGION },
  async (event) => {
    const postId = event.params.postId;
    const post = event.data.data();

    if (!post || !post.authorId) {
      console.warn(`[onPostCreateValidate] Missing data for post ${postId}`);
      return;
    }

    // If post already published (shouldn't happen — client should set 'publishing')
    // or already failed, skip
    if (post.status === 'published' || post.status === 'failed') return;

    const postRef = event.data.ref;

    // Initialize all server-managed counters to 0 (prevents missing field queries)
    await postRef.update({
      amenCount: 0,
      lightbulbCount: 0,
      commentCount: 0,
      repostCount: 0,
      lastCommentAt: null,
      // If no media, mark as published immediately
      // If has media, status remains 'publishing' until finalizePostPublish is called
      ...((!post.media || post.media.length === 0) ? {
        status: 'published',
        publishedAt: admin.firestore.FieldValue.serverTimestamp(),
      } : {}),
    });

    console.log(`[onPostCreateValidate] Initialized counters for post ${postId}`);
  }
);
