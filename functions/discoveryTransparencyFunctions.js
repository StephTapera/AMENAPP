/**
 * discoveryTransparencyFunctions.js
 * Phase 4 — Spatial Social OS: Discovery transparency ("Why am I seeing this?").
 *
 * Single callable, `getDiscoveryReasons`, that explains WHY a particular post
 * surfaced in the user's feed. Reasons are SERVER-DERIVED — the client never
 * invents a reason or label. The mapping below is the authoritative source
 * of user-visible language, matching the codes already used by the iOS
 * `DiscoveryFeedItem.DiscoveryReason` enum.
 *
 * Reason codes:
 *   followed_topic, friend_interaction, local_community, church_content,
 *   trusted_creator, you_might_know, slow_feed
 *
 * Each returned row is:
 *   { code, label, explanation, icon, weight }
 *
 * Callable: getDiscoveryReasons
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = () => admin.firestore();

const REASON_TEXT = {
  followed_topic: {
    label: "Topic you follow",
    explanation: "This post is tagged with a topic you've chosen to follow.",
    icon: "tag",
  },
  friend_interaction: {
    label: "From someone you follow",
    explanation: "You follow this creator, so their recent posts appear in your feed.",
    icon: "person.2",
  },
  local_community: {
    label: "From your community",
    explanation: "Other people in a community you've joined have engaged with this post.",
    icon: "mappin.and.ellipse",
  },
  church_content: {
    label: "From a church you follow",
    explanation: "This post comes from a church or ministry community you've joined.",
    icon: "building.columns",
  },
  trusted_creator: {
    label: "Trusted creator",
    explanation: "This creator has verified provenance on their media and a strong safety record.",
    icon: "checkmark.seal",
  },
  you_might_know: {
    label: "You might know them",
    explanation: "You and this creator share several mutual connections.",
    icon: "person.crop.circle.badge.questionmark",
  },
  slow_feed: {
    label: "Mindful pick",
    explanation: "Curated as a slow-feed pick to support calm, intentional reading.",
    icon: "leaf",
  },
};

function reasonRow(code, weight) {
  const text = REASON_TEXT[code];
  if (!text) return null;
  return {
    code,
    label: text.label,
    explanation: text.explanation,
    icon: text.icon,
    weight,
  };
}

exports.getDiscoveryReasons = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {postId} = request.data || {};
      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }

      const postSnap = await db().collection("posts").doc(postId).get();
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "Post not found");
      }
      const post = postSnap.data() || {};
      const authorId = post.authorId || post.userId || post.ownerUid || null;

      const reasons = [];

      // 1. Following relationship.
      if (authorId && authorId !== uid) {
        const followingDoc = await db()
            .collection("users").doc(uid)
            .collection("following").doc(authorId)
            .get();
        if (followingDoc.exists) {
          reasons.push(reasonRow("friend_interaction", 0.9));
        }
      }

      // 2. Trusted creator: provenance verified + clean moderation.
      // We use any provenance doc for the post — first one wins.
      const provSnap = await db()
          .collection("provenance")
          .where("postId", "==", postId)
          .limit(1)
          .get();
      if (!provSnap.empty) {
        const prov = provSnap.docs[0].data() || {};
        const verified = prov.contentCredentialsStatus === "verified";
        const safe = prov.moderationStatus !== "blocked"
          && prov.syntheticMediaStatus !== "deepfake_risk"
          && (prov.authenticityConfidence || 0) >= 0.8;
        if (verified || safe) {
          reasons.push(reasonRow("trusted_creator", 0.8));
        }
      }

      // 3. Followed topic — intersect post tags with user followed topics.
      const postTags = Array.isArray(post.topicTags) ? post.topicTags
        : (Array.isArray(post.tags) ? post.tags : []);
      if (postTags.length > 0) {
        const userDoc = await db().collection("users").doc(uid).get();
        const userData = userDoc.exists ? (userDoc.data() || {}) : {};
        const followed = Array.isArray(userData.followedTopics)
          ? userData.followedTopics
          : (Array.isArray(userData.topics) ? userData.topics : []);
        const overlap = postTags.some((t) => followed.includes(t));
        if (overlap) {
          reasons.push(reasonRow("followed_topic", 0.75));
        }
      }

      // 4. Church / community content.
      if (post.communityId || post.churchId) {
        const target = post.communityId || post.churchId;
        const memberDoc = await db()
            .collection("users").doc(uid)
            .collection("communities").doc(target)
            .get();
        if (memberDoc.exists) {
          reasons.push(reasonRow("church_content", 0.7));
        }
      }

      // 5. Slow feed default — only if nothing else matched.
      if (reasons.length === 0) {
        reasons.push(reasonRow("slow_feed", 0.4));
      }

      // Filter nulls and de-dupe by code (highest weight wins).
      const byCode = new Map();
      for (const r of reasons) {
        if (!r) continue;
        const existing = byCode.get(r.code);
        if (!existing || existing.weight < r.weight) {
          byCode.set(r.code, r);
        }
      }
      const ordered = Array.from(byCode.values())
          .sort((a, b) => b.weight - a.weight);

      // Log the explanation request for transparency analytics. Best-effort —
      // a failure here does not block the response.
      try {
        await db().collection("discoveryEvents").add({
          uid,
          postId,
          surface: "feed",
          reasons: ordered.map((r) => r.code),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Swallow — transparency must work even if analytics write fails.
      }

      return {postId, reasons: ordered};
    },
);
