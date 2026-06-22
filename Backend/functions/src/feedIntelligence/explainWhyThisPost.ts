import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAuth, requireAppCheck } from "./moderation";
import type { FeedIntelligenceProfile } from "./types";

export const explainWhyThisPost = onCall(
  { enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
  async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);
    const postId = request.data?.postId as string | undefined;
    if (!postId) throw new HttpsError("invalid-argument", "postId required.");

    const db = admin.firestore();

    // Verify post exists and is accessible
    const postSnap = await db.doc(`posts/${postId}`).get();
    if (!postSnap.exists) throw new HttpsError("not-found", "Post not found.");

    const postData = postSnap.data() ?? {};
    const [profileSnap, signalsSnap] = await Promise.all([
      db.doc(`users/${uid}/feedIntelligence/profile/main`).get(),
      db.collection(`users/${uid}/feedIntelligence/signals`)
        .where("status", "==", "active")
        .orderBy("createdAt", "desc")
        .limit(5)
        .get(),
    ]);

    const profile = (profileSnap.exists ? profileSnap.data() : null) as FeedIntelligenceProfile | null;
    const reasons: string[] = [];
    const preferenceSignals: string[] = [];
    const safetyNotes: string[] = [];

    // Match against active signals
    for (const signalDoc of signalsSnap.docs) {
      const signal = signalDoc.data();
      const matches = (signal.topicsIncreased ?? []).some((t: string) => {
        const postTags: string[] = postData["tags"] ?? postData["topics"] ?? [];
        return postTags.some((pt) => pt.toLowerCase().includes(t.toLowerCase()) || t.toLowerCase().includes(pt.toLowerCase()));
      });
      if (matches) {
        reasons.push(`You recently asked for more ${signal.topicsIncreased?.[0] ?? "of this content"}.`);
        preferenceSignals.push(`Guide My Feed: ${signal.interpretedSummary}`);
      }
    }

    // Profile-based explanation
    if (profile?.feedHealth.preferCalmContent) {
      reasons.push("Your feed is set to prefer calmer, more uplifting content.");
    }
    if (profile && Object.keys(profile.boostedTopics).length > 0) {
      const boosted = Object.keys(profile.boostedTopics).slice(0, 2);
      reasons.push(`This post matches your interest in ${boosted.join(" and ")}.`);
    }

    // Fallback
    if (reasons.length === 0) {
      reasons.push("This post is part of your general recommendations.");
    }

    return {
      postId,
      title: "Why this post?",
      reasons: reasons.slice(0, 4),
      feedSignals: [],
      preferenceSignals: preferenceSignals.slice(0, 3),
      safetyNotes,
      canAdjust: true,
    };
  }
);
