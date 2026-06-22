import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAuth, requireAppCheck } from "./moderation";
import type { PostRecommendationAction } from "./types";

export const adjustPostRecommendationSignal = onCall(
  { enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
  async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);
    const { postId, action } = request.data as { postId: string; action: PostRecommendationAction };

    if (!postId || !action) throw new HttpsError("invalid-argument", "postId and action required.");

    const db = admin.firestore();
    const postSnap = await db.doc(`posts/${postId}`).get();
    if (!postSnap.exists) throw new HttpsError("not-found", "Post not found.");

    const postData = postSnap.data() ?? {};
    const tags: string[] = postData["tags"] ?? postData["topics"] ?? [];

    const profileRef = db.doc(`users/${uid}/feedIntelligence/profile/main`);
    const eventRef = db.collection(`users/${uid}/feedIntelligence/events`).doc();

    const profileUpdate: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    switch (action) {
      case "more_like_this":
        for (const tag of tags.slice(0, 3)) {
          profileUpdate[`boostedTopics.${tag}`] = admin.firestore.FieldValue.increment(0.5);
        }
        break;
      case "less_like_this":
        for (const tag of tags.slice(0, 3)) {
          profileUpdate[`suppressedTopics.${tag}`] = admin.firestore.FieldValue.increment(0.5);
        }
        break;
      case "hide_topic":
        for (const tag of tags.slice(0, 2)) {
          profileUpdate[`suppressedTopics.${tag}`] = admin.firestore.FieldValue.increment(1.0);
        }
        break;
      case "hide_creator":
        if (postData["authorId"]) {
          profileUpdate[`creatorAffinities.${postData["authorId"]}`] = -2.0;
        }
        break;
      case "reset_related":
        for (const tag of tags.slice(0, 3)) {
          profileUpdate[`boostedTopics.${tag}`] = admin.firestore.FieldValue.delete();
          profileUpdate[`suppressedTopics.${tag}`] = admin.firestore.FieldValue.delete();
        }
        break;
    }

    await Promise.all([
      profileRef.set(profileUpdate, { merge: true }),
      eventRef.set({
        eventType: `post_recommendation_${action}`,
        postId,
        metadata: { tags, action },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
    ]);

    return { success: true, action, postId };
  }
);
