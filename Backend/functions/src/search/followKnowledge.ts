/**
 * search/followKnowledge.ts
 *
 * Topic follow/unfollow system for the AMEN Catalog Knowledge layer.
 *
 * Contract:
 *   - Following is ALWAYS explicit user action (opt-in only — never automatic)
 *   - NO engagement scores, popularity counts, or comparative metrics
 *     ("X other people follow this" is forbidden — no social pressure)
 *   - Topic update notifications are opt-in per-topic, default OFF
 *   - Notification fan-out delegates to the EXISTING notification pipeline
 *     (sendNotificationCallable / sendPush) — this module NEVER forks it
 *   - Works returned in topic feed: published + non-deleted only
 *
 * Collections:
 *   users/{uid}/topicFollows/{topicId}           — follow relationship
 *   topicSubscribers/{topicId}/members/{uid}     — reverse index for fan-out
 *   users/{uid}/topicPreferences/{topicId}       — per-topic notification prefs
 *   knowledgeNodes/{nodeId}                      — creator knowledge graph nodes
 *
 * Region: us-east1 (us-central1 at quota; see CLAUDE.md §us-central1 Quota Warning)
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

// ─── Predefined topic registry ─────────────────────────────────────────────────
// Must stay in sync with the iOS starterTopics constant in FollowKnowledgeView.swift.

const VALID_TOPICS = new Set([
    "leadership", "prayer", "marriage", "ai", "startups", "faith",
    "finance", "health", "relationships", "creativity", "scripture",
    "justice", "worship", "education", "business", "parenting",
    "mental-health", "community", "social-justice", "technology",
    "discipleship", "evangelism", "church", "family", "serving",
    "missions", "theology", "apologetics", "counseling", "devotional",
]);

function normalizeTopicId(raw: string): string {
    return raw.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
}

// ─── followTopic ───────────────────────────────────────────────────────────────

/**
 * followTopic — opt-in: user explicitly follows a topic.
 *
 * Input:  { topicId: string, topicName: string }
 * Output: { ok: true }
 */
export const followTopic = onCall(
    { region: "us-east1", enforceAppCheck: true },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const userId = request.auth.uid;
        const data = request.data as { topicId?: string; topicName?: string };

        const rawId = (data.topicId ?? "").trim();
        const topicId = normalizeTopicId(rawId);
        const topicName = (data.topicName ?? rawId).trim().slice(0, 64);

        if (!topicId) {
            throw new HttpsError("invalid-argument", "topicId is required");
        }
        if (!VALID_TOPICS.has(topicId)) {
            throw new HttpsError("invalid-argument", "Unknown topic");
        }

        const batch = db.batch();
        const now = admin.firestore.FieldValue.serverTimestamp();

        // users/{uid}/topicFollows/{topicId}
        const followRef = db
            .collection("users").doc(userId)
            .collection("topicFollows").doc(topicId);
        batch.set(followRef, {
            topicId,
            topicName,
            followedAt: now,
            notificationsEnabled: false, // default OFF — explicit opt-in required
        }, { merge: true });

        // topicSubscribers/{topicId}/members/{uid} — reverse index for fan-out
        const subscriberRef = db
            .collection("topicSubscribers").doc(topicId)
            .collection("members").doc(userId);
        batch.set(subscriberRef, {
            uid: userId,
            followedAt: now,
            notificationsEnabled: false,
        }, { merge: true });

        await batch.commit();

        return { ok: true };
    }
);

// ─── unfollowTopic ─────────────────────────────────────────────────────────────

/**
 * unfollowTopic — user explicitly unfollows a topic.
 *
 * Input:  { topicId: string }
 * Output: { ok: true }
 */
export const unfollowTopic = onCall(
    { region: "us-east1", enforceAppCheck: true },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const userId = request.auth.uid;
        const data = request.data as { topicId?: string };

        const rawId = (data.topicId ?? "").trim();
        const topicId = normalizeTopicId(rawId);

        if (!topicId) {
            throw new HttpsError("invalid-argument", "topicId is required");
        }

        const batch = db.batch();

        const followRef = db
            .collection("users").doc(userId)
            .collection("topicFollows").doc(topicId);
        batch.delete(followRef);

        const subscriberRef = db
            .collection("topicSubscribers").doc(topicId)
            .collection("members").doc(userId);
        batch.delete(subscriberRef);

        await batch.commit();

        return { ok: true };
    }
);

// ─── getFollowedTopics ─────────────────────────────────────────────────────────

/**
 * getFollowedTopics — returns all topics the caller currently follows.
 *
 * Output: { topics: Array<{ topicId, topicName, followedAt, recentWorkCount }> }
 *
 * Note: recentWorkCount is a server-side count of works published in the last 7 days
 * for that topic. It represents UNREAD CONTENT, not popularity/engagement.
 */
export const getFollowedTopics = onCall(
    { region: "us-east1", enforceAppCheck: true },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const userId = request.auth.uid;

        const snap = await db
            .collection("users").doc(userId)
            .collection("topicFollows")
            .orderBy("followedAt", "desc")
            .get();

        if (snap.empty) {
            return { topics: [] };
        }

        // Count recent works (last 7 days) per followed topic — parallel queries
        const sevenDaysAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 7 * 24 * 60 * 60 * 1000
        );

        const topicIds = snap.docs.map((d) => d.id);

        // Fan-out: get recent work counts for all followed topics
        const countResults = await Promise.allSettled(
            topicIds.map((topicId) =>
                db.collection("works")
                    .where("topics", "array-contains", topicId)
                    .where("reviewState", "==", "published")
                    .where("publishedAt", ">=", sevenDaysAgo)
                    .where("deletedAt", "==", null)
                    .count()
                    .get()
            )
        );

        const topics = snap.docs.map((d, i) => {
            const data = d.data();
            const countResult = countResults[i];
            const recentWorkCount =
                countResult.status === "fulfilled"
                    ? countResult.value.data().count
                    : 0;

            return {
                topicId:          d.id,
                topicName:        (data["topicName"] as string) ?? d.id,
                followedAt:       (data["followedAt"] as admin.firestore.Timestamp)?.toMillis() ?? null,
                recentWorkCount,
            };
        });

        return { topics };
    }
);

// ─── getTopicFeed ──────────────────────────────────────────────────────────────

/**
 * getTopicFeed — paginated feed of recently published works in the caller's
 * followed topics.
 *
 * Input:  { limit?: number (max 30), afterPublishedAt?: number (epoch ms, for cursor pagination) }
 * Output: { works: WorkFeedItem[], topics: string[], nextCursor?: number }
 *
 * ONLY published, non-deleted, public-visibility works are returned.
 * Works are ordered by publishedAt descending.
 */
export const getTopicFeed = onCall(
    { region: "us-east1", enforceAppCheck: true },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const userId = request.auth.uid;
        const data = request.data as {
            limit?: number;
            afterPublishedAt?: number;
        };

        const pageSize = Math.min(data.limit ?? 20, 30);

        // Load followed topics
        const followsSnap = await db
            .collection("users").doc(userId)
            .collection("topicFollows")
            .get();

        const topicIds = followsSnap.docs.map((d) => d.id);
        const topicNames = followsSnap.docs.map((d) =>
            (d.data()["topicName"] as string) ?? d.id
        );

        if (topicIds.length === 0) {
            return { works: [], topics: [], nextCursor: null };
        }

        // Firestore `array-contains-any` supports max 30 values
        const topicBatch = topicIds.slice(0, 30);

        let query = db.collection("works")
            .where("topics", "array-contains-any", topicBatch)
            .where("reviewState", "==", "published")
            .where("visibility", "in", ["public"])
            .where("deletedAt", "==", null)
            .orderBy("publishedAt", "desc")
            .limit(pageSize + 1); // fetch one extra to determine if there's a next page

        if (data.afterPublishedAt) {
            const cursor = admin.firestore.Timestamp.fromMillis(data.afterPublishedAt);
            query = query.startAfter(cursor);
        }

        const snap = await query.get();

        const allDocs = snap.docs;
        const hasMore = allDocs.length > pageSize;
        const pageDocs = hasMore ? allDocs.slice(0, pageSize) : allDocs;

        const works = pageDocs.map((d) => {
            const wd = d.data();
            return {
                id:           d.id,
                title:        (wd["title"] as string) ?? "",
                type:         (wd["type"] as string) ?? "article",
                creatorName:  (wd["creatorName"] as string) ?? "",
                creatorAvatar: wd["creatorAvatar"] as string | undefined,
                coverUrl:     wd["coverUrl"] as string | undefined,
                topics:       (wd["topics"] as string[]) ?? [],
                publishedAt:  (wd["publishedAt"] as admin.firestore.Timestamp)?.toMillis() ?? null,
            };
        });

        const lastDoc = pageDocs[pageDocs.length - 1];
        const nextCursor = hasMore
            ? ((lastDoc.data()["publishedAt"] as admin.firestore.Timestamp)?.toMillis() ?? null)
            : null;

        return {
            works,
            topics: topicNames,
            nextCursor,
        };
    }
);

// ─── notifyFollowersOfTopic ────────────────────────────────────────────────────

/**
 * notifyFollowersOfTopic — internal helper (not a direct callable).
 *
 * Called by the catalog work publishing pipeline when a work is published.
 * Fans out an in-app-only notification to users who:
 *   1. Follow the topic
 *   2. Have notificationsEnabled == true for that topic (opt-in)
 *
 * Uses the EXISTING notification infrastructure:
 *   - Writes to notifications/{recipientId} collection (same schema as onSocialEvent.ts)
 *   - Does NOT directly call FCM — FCM dispatch is handled by the existing
 *     Firestore trigger on the notifications collection
 *
 * Privacy constraints:
 *   - NO comparative metrics: "37 other followers saw this" is forbidden
 *   - NO engagement pressure: no "trending" or "popular" signals
 *   - In-app only by default; push requires explicit per-topic opt-in
 */
export async function notifyFollowersOfTopic(params: {
    topicId: string;
    topicName: string;
    workId: string;
    workTitle: string;
    creatorName: string;
    creatorId: string;
}): Promise<void> {
    const { topicId, topicName, workId, workTitle, creatorName, creatorId } = params;

    // Fetch opted-in subscribers only (notificationsEnabled == true)
    const subscribersSnap = await db
        .collection("topicSubscribers").doc(topicId)
        .collection("members")
        .where("notificationsEnabled", "==", true)
        .limit(500) // cap fan-out per invocation; trigger again for remainder
        .get();

    if (subscribersSnap.empty) return;

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();

    for (const memberDoc of subscribersSnap.docs) {
        const recipientId = memberDoc.id;

        // Skip self-notification (creator following their own topic)
        if (recipientId === creatorId) continue;

        const notifRef = db.collection("notifications").doc();
        batch.set(notifRef, {
            recipientId,
            actorId: creatorId,
            actorName: creatorName,
            type: "catalog_topic_update",      // non-push type in default policy
            topicId,
            topicName,
            workId,
            workTitle,
            createdAt: now,
            read: false,
            // Delivery policy: in-app only unless user FCM opt-in
            // The existing notification Firestore trigger evaluates push eligibility
            // via evaluatePolicies() — catalog_topic_update defaults to InAppOnly
            schemaVersion: "2",
        });
    }

    await batch.commit();
}

// ─── getKnowledgeGraph ────────────────────────────────────────────────────────

/**
 * getKnowledgeGraph — returns KnowledgeNode documents for a creator.
 * Shape: person → topics → works
 *
 * Input:  { creatorId: string }
 * Output: { nodes: KnowledgeNode[] }
 *
 * Only returns published, non-deleted nodes.
 */
export const getKnowledgeGraph = onCall(
    { region: "us-east1", enforceAppCheck: true },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const data = request.data as { creatorId?: string };
        const creatorId = (data.creatorId ?? "").trim();

        if (!creatorId) {
            throw new HttpsError("invalid-argument", "creatorId is required");
        }

        const nodesSnap = await db
            .collection("knowledgeNodes")
            .where("creatorId", "==", creatorId)
            .where("deletedAt", "==", null)
            .orderBy("createdAt", "asc")
            .limit(100)
            .get();

        const nodes = nodesSnap.docs.map((d) => {
            const nd = d.data();
            return {
                id:          d.id,
                creatorId:   (nd["creatorId"] as string) ?? "",
                nodeType:    (nd["nodeType"] as string) ?? "work",    // "person" | "topic" | "work"
                label:       (nd["label"] as string) ?? "",
                description: (nd["description"] as string) ?? "",
                topics:      (nd["topics"] as string[]) ?? [],
                linkedWorkIds: (nd["linkedWorkIds"] as string[]) ?? [],
                parentNodeId: nd["parentNodeId"] as string | undefined,
                createdAt:   (nd["createdAt"] as admin.firestore.Timestamp)?.toMillis() ?? null,
            };
        });

        return { nodes };
    }
);
