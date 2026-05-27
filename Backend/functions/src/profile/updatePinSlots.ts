/**
 * updatePinSlots.ts
 *
 * Cloud Function (Gen2 onCall): `updatePinSlots`
 *
 * Allows a user to set up to 3 pinned post slots on their profile.
 * Owner-only: the caller must own every post they try to pin.
 *
 * Request:  { postIds: string[] }  — array of post document IDs (max 3)
 * Response: { success: true, pinSlotIds: string[] }
 *
 * Error codes:
 *   unauthenticated  — caller is not signed in
 *   invalid-argument — postIds missing, not an array, or longer than 3
 *   permission-denied — post does not belong to the calling user
 *   not-found        — one or more post IDs do not exist in `posts`
 *   internal         — unexpected Firestore failure
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const updatePinSlots = onCall(async (request) => {
  // 1. Auth guard
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in to update pin slots.");
  }

  const uid = request.auth.uid;

  // 2. Input validation
  const { postIds } = (request.data ?? {}) as { postIds?: unknown };

  if (!Array.isArray(postIds)) {
    throw new HttpsError("invalid-argument", "postIds must be an array of post ID strings.");
  }

  if (postIds.length > 3) {
    throw new HttpsError(
      "invalid-argument",
      `Pin slots are limited to 3. Received ${postIds.length}.`
    );
  }

  // Validate every element is a non-empty string
  for (let i = 0; i < postIds.length; i++) {
    if (typeof postIds[i] !== "string" || (postIds[i] as string).trim() === "") {
      throw new HttpsError(
        "invalid-argument",
        `postIds[${i}] must be a non-empty string.`
      );
    }
  }

  const validatedPostIds = postIds as string[];

  const db = admin.firestore();

  // 3. Verify each post exists and belongs to the calling user
  if (validatedPostIds.length > 0) {
    let postSnaps: admin.firestore.DocumentSnapshot[];
    try {
      const postRefs = validatedPostIds.map((id) => db.collection("posts").doc(id));
      postSnaps = await db.getAll(...postRefs);
    } catch {
      throw new HttpsError("internal", "Failed to verify post ownership.");
    }

    for (let i = 0; i < postSnaps.length; i++) {
      const snap = postSnaps[i];
      const postId = validatedPostIds[i];

      if (!snap.exists) {
        throw new HttpsError("not-found", `Post '${postId}' does not exist.`);
      }

      const postData = snap.data() ?? {};
      if (postData.authorId !== uid) {
        throw new HttpsError(
          "permission-denied",
          `Post '${postId}' does not belong to the calling user.`
        );
      }
    }
  }

  // 4. Write pin slots to users/{uid}.profile.pinSlots
  try {
    await db.collection("users").doc(uid).set(
      { profile: { pinSlots: validatedPostIds } },
      { merge: true }
    );
  } catch {
    throw new HttpsError("internal", "Failed to save pin slots.");
  }

  return { success: true, pinSlotIds: validatedPostIds };
});
