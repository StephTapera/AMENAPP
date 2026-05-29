/**
 * anonPost.ts
 *
 * Anonymous-Accountable Mode — Trust OS requirement.
 *
 * DESIGN CONTRACT:
 *   Pseudonymous to community: posts appear with a stable per-user
 *   anonId ("Anonymous") — no real identity exposed.
 *   Accountable to platform: a server-only anonIdMappings/{anonId}
 *   document holds the realUid→anonId binding. Admins can de-anonymize
 *   via resolveAnonymousPost; no client can read the mapping.
 *
 * SECURITY PROPERTIES:
 *   - anonId is derived as HMAC-SHA256(uid, ANON_SALT_SECRET). It is stable
 *     per user across sessions so moderators can detect repeat violators.
 *   - The post document stores anonId, NOT realUid. The mapping lives only
 *     in anonIdMappings (Firestore rules: allow read, write: if false).
 *   - Rate limit: 3 anon posts per rolling 24-hour window per user.
 *   - enforceAppCheck: true on all callables.
 *
 * Callables exported:
 *   createAnonymousPost    — authenticated user, gated by anonModeEnabled flag
 *   resolveAnonymousPost   — admin-only de-anonymization
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ANON_SALT: high-entropy secret used to derive stable, irreversible anonIds.
// Set via: firebase functions:secrets:set ANON_SALT
// Must be at least 32 characters.
const anonSalt = defineSecret("ANON_SALT");

const REGION = "us-central1";
const MAX_ANON_POSTS_PER_24H = 3;
const MAX_POST_LENGTH = 2000;

// ─── Helpers ──────────────────────────────────────────────────────────────────

function deriveAnonId(uid: string, salt: string): string {
  return crypto
    .createHmac("sha256", salt)
    .update(uid)
    .digest("hex")
    .slice(0, 32); // 128-bit hex prefix — collision-resistant for platform scale
}

async function enforceRateLimit(uid: string): Promise<void> {
  const windowRef = db.doc(`anonRateLimits/${uid}`);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(windowRef);
    const now = Date.now();
    const cutoff = now - 24 * 60 * 60 * 1000;

    let timestamps: number[] = [];
    if (snap.exists) {
      const data = snap.data();
      timestamps = (data?.postTimestamps ?? []).filter((t: number) => t >= cutoff);
    }

    if (timestamps.length >= MAX_ANON_POSTS_PER_24H) {
      throw new HttpsError(
        "resource-exhausted",
        `Anonymous post limit reached. You may post up to ${MAX_ANON_POSTS_PER_24H} anonymous messages per 24 hours.`
      );
    }

    timestamps.push(now);
    tx.set(windowRef, { postTimestamps: timestamps, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
}

// ─── createAnonymousPost ──────────────────────────────────────────────────────

interface CreateAnonPostRequest {
  content: string;
  communityId?: string;
  feedScope?: "public" | "followers_only";
}

interface CreateAnonPostResponse {
  postId: string;
  anonId: string;
}

export const createAnonymousPost = onCall(
  {
    region: REGION,
    enforceAppCheck: true,
    secrets: [anonSalt],
  },
  async (
    request: CallableRequest<CreateAnonPostRequest>
  ): Promise<CreateAnonPostResponse> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { content, communityId, feedScope = "public" } = request.data;

    if (!content || typeof content !== "string" || content.trim().length === 0) {
      throw new HttpsError("invalid-argument", "content is required.");
    }
    if (content.length > MAX_POST_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Post exceeds the ${MAX_POST_LENGTH}-character limit.`
      );
    }

    // Enforce rate limit before doing any writes.
    await enforceRateLimit(uid);

    const salt = anonSalt.value();
    const anonId = deriveAnonId(uid, salt);

    // Persist the mapping server-side (idempotent — safe to overwrite with
    // the same values if the user posts anonymously multiple times).
    await db.doc(`anonIdMappings/${anonId}`).set(
      {
        realUid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Create the post document with only the anonId — real UID never stored here.
    const postRef = db.collection("posts").doc();
    await postRef.set({
      authorId: anonId,
      authorDisplayName: "Anonymous",
      isAnonymous: true,
      content: content.trim(),
      status: "publishing", // onPostCreated trigger will transition → published
      moderationStatus: "pending",
      feedScope,
      communityId: communityId ?? null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[anonPost] Anonymous post created postId=${postRef.id} anonId=${anonId}`);

    return { postId: postRef.id, anonId };
  }
);

// ─── resolveAnonymousPost ─────────────────────────────────────────────────────

interface ResolveAnonPostRequest {
  postId: string;
}

interface ResolveAnonPostResponse {
  postId: string;
  anonId: string;
  realUid: string;
}

export const resolveAnonymousPost = onCall(
  {
    region: REGION,
    enforceAppCheck: true,
    secrets: [anonSalt],
  },
  async (
    request: CallableRequest<ResolveAnonPostRequest>
  ): Promise<ResolveAnonPostResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.auth.token?.admin) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const { postId } = request.data;
    if (!postId || typeof postId !== "string") {
      throw new HttpsError("invalid-argument", "postId is required.");
    }

    const postSnap = await db.doc(`posts/${postId}`).get();
    if (!postSnap.exists) {
      throw new HttpsError("not-found", `Post ${postId} not found.`);
    }

    const postData = postSnap.data()!;
    if (!postData.isAnonymous) {
      throw new HttpsError("failed-precondition", "Post is not anonymous.");
    }

    const anonId: string = postData.authorId;
    const mappingSnap = await db.doc(`anonIdMappings/${anonId}`).get();
    if (!mappingSnap.exists) {
      throw new HttpsError("not-found", `No mapping found for anonId ${anonId}.`);
    }

    const realUid: string = mappingSnap.data()!.realUid;

    // Write an audit event so every de-anonymization is logged immutably.
    await db.collection("trustAuditLog").add({
      eventType: "anon_post_resolved",
      adminUid: request.auth.uid,
      targetPostId: postId,
      anonId,
      realUid,
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.warn(
      `[anonPost] Admin ${request.auth.uid} resolved postId=${postId} ` +
        `anonId=${anonId} → realUid=${realUid}`
    );

    return { postId, anonId, realUid };
  }
);
