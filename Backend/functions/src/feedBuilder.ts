import {
    onDocumentCreated,
    onDocumentDeleted,
    onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

const FEED_BATCH_LIMIT = 400;

// HIGH FIX: Feed fanout architecture note.
//
// CURRENT APPROACH (synchronous fan-out):
//   writeFeedItems() queries all followers then writes a feed doc for each.
//   For a pastor with 100K followers this is ~100K sequential Firestore writes
//   in a single function invocation, blocking a 9-minute timeout.
//
// RECOMMENDED MIGRATION — Pub/Sub fan-out (implement when follower counts exceed ~5K):
//   1. Publish a single message to a Pub/Sub topic ("feed-fanout") containing
//      { postId, authorId, feedData } from onPostCreateFeed.
//   2. A subscriber Cloud Function reads the topic and processes followers in
//      parallel shards (e.g. 500 followers per worker, 10 workers in parallel).
//   3. Each worker writes its shard with a batched Firestore write (500 writes/batch).
//   This reduces wall-clock time from O(followers) serial to O(ceil(followers/500))
//   parallel, and eliminates the single-function OOM/timeout risk.
//
// INTERIM MITIGATION (active):
//   - Per-minute fanout rate throttle prevents burst abuse (MAX_FANOUTS_PER_MINUTE).
//   - FEED_FANOUT_FOLLOWER_CAP caps the fanout at MAX_FANOUT_FOLLOWERS followers;
//     accounts above this threshold should be migrated to Pub/Sub before launch.
//     This prevents a single viral post from consuming the entire function quota.
//
const MAX_FANOUTS_PER_MINUTE = 10;

// Cap on how many followers receive a fan-out write in a single invocation.
// Accounts with more followers than this need the Pub/Sub migration above.
// At 400 writes/batch × 9-minute timeout ≈ ~30K writes safely possible, but
// we cap lower to keep p99 latency reasonable and leave headroom for retries.
const MAX_FANOUT_FOLLOWERS = 5000;

/**
 * Check if the author has exceeded the fanout rate limit.
 * Returns true when the fanout should be skipped (throttled).
 * Does NOT throw — Firestore triggers must handle errors gracefully.
 */
async function isFanoutThrottled(authorId: string): Promise<boolean> {
    const now = Date.now();
    const windowMs = 60_000;
    const windowStart = Math.floor(now / windowMs) * windowMs;
    const docId = `fanout_1min_${windowStart}`;
    const ref = db.collection("rateLimits").doc(authorId)
                  .collection("windows").doc(docId);

    try {
        let throttled = false;
        await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const data = snap.exists
                ? (snap.data() as { count: number; windowEnd: number })
                : null;
            const windowEnd   = windowStart + windowMs;
            const currentCount = (data && data.windowEnd > now) ? data.count : 0;

            if (currentCount >= MAX_FANOUTS_PER_MINUTE) {
                throttled = true;
                return;
            }

            tx.set(ref, {
                count: currentCount + 1,
                windowEnd,
                uid: authorId,
                limitName: "fanout_1min",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
        return throttled;
    } catch (e) {
        // If the rate check itself fails, allow the fanout through to avoid
        // silently dropping legitimate posts.
        logger.error("[FeedBuilder] Rate limit check error — allowing fanout", e);
        return false;
    }
}

function normalizeVisibility(raw: unknown): string {
    if (typeof raw !== "string") { return "everyone"; }
    return raw.trim().toLowerCase();
}

async function writeFeedItems(
    postId: string,
    authorId: string,
    feedData: Record<string, unknown>
): Promise<void> {
    // HIGH FIX: Cap followers fetched per invocation.
    // Accounts above MAX_FANOUT_FOLLOWERS must be migrated to Pub/Sub fan-out
    // before their follower count reaches this limit to avoid timeout/OOM.
    const followersSnap = await db
        .collection("users")
        .doc(authorId)
        .collection("followers")
        .limit(MAX_FANOUT_FOLLOWERS)
        .get();

    const followerIds = followersSnap.docs.map((doc) => doc.id);
    if (followersSnap.size >= MAX_FANOUT_FOLLOWERS) {
        logger.warn(
            `[FeedBuilder] Author ${authorId} has >= ${MAX_FANOUT_FOLLOWERS} followers. ` +
            `Fan-out capped — migrate to Pub/Sub for full delivery.`
        );
    }

    // Mode filter: skip recipients who have opted into modes where canViewPublicFeed is false.
    // "quiet" and "study" users have chosen to limit their feed — respect that choice.
    // We batch-fetch recipient modes to avoid N individual reads.
    const MODES_WITHOUT_PUBLIC_FEED = new Set(["quiet", "study"]);
    let filteredFollowerIds = followerIds;
    if (followerIds.length > 0) {
        try {
            // Fetch in batches of 400 (Firestore getAll limit)
            const modeFilteredIds: string[] = [];
            for (let i = 0; i < followerIds.length; i += 400) {
                const chunk = followerIds.slice(i, i + 400);
                const refs = chunk.map((id) => db.collection("users").doc(id));
                const snaps = await db.getAll(...refs);
                for (const snap of snaps) {
                    const mode = snap.exists ? (snap.data()?.interactionMode as string | undefined) : undefined;
                    if (!mode || !MODES_WITHOUT_PUBLIC_FEED.has(mode)) {
                        modeFilteredIds.push(snap.id);
                    }
                }
            }
            filteredFollowerIds = modeFilteredIds;
            if (filteredFollowerIds.length < followerIds.length) {
                logger.info(
                    `[FeedBuilder] Mode filter: skipped ${followerIds.length - filteredFollowerIds.length} ` +
                    `recipients in quiet/study mode for post ${postId ?? "unknown"}`
                );
            }
        } catch (modeFilterErr) {
            // Non-fatal: if mode fetch fails, deliver to all followers
            logger.warn("[FeedBuilder] Mode filter failed — delivering to all followers", modeFilterErr);
            filteredFollowerIds = followerIds;
        }
    }

    const targets = Array.from(new Set([authorId, ...filteredFollowerIds]));

    for (let i = 0; i < targets.length; i += FEED_BATCH_LIMIT) {
        const batch = db.batch();
        const chunk = targets.slice(i, i + FEED_BATCH_LIMIT);
        for (const userId of chunk) {
            const ref = db.collection("feeds").doc(userId).collection("items").doc(postId);
            batch.set(ref, feedData, { merge: true });
        }
        await batch.commit();
    }
}

async function deleteFeedItems(postId: string, authorId: string): Promise<void> {
    const followersSnap = await db
        .collection("users")
        .doc(authorId)
        .collection("followers")
        .get();

    const followerIds = followersSnap.docs.map((doc) => doc.id);
    const targets = Array.from(new Set([authorId, ...followerIds]));

    for (let i = 0; i < targets.length; i += FEED_BATCH_LIMIT) {
        const batch = db.batch();
        const chunk = targets.slice(i, i + FEED_BATCH_LIMIT);
        for (const userId of chunk) {
            const ref = db.collection("feeds").doc(userId).collection("items").doc(postId);
            batch.delete(ref);
        }
        await batch.commit();
    }
}

const BLOCKED_MODERATION_STATUSES = ["blocked", "escalated", "removed_after_publish"];

export const onPostCreateFeed = onDocumentCreated("posts/{postId}", async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    const postId = event.params.postId;
    const authorId = data.authorId as string | undefined;
    if (!authorId) return;

    // Safety OS: never fan out blocked or escalated content into follower feeds.
    const moderationStatus = data.moderationStatus as string | undefined;
    if (moderationStatus && BLOCKED_MODERATION_STATUSES.includes(moderationStatus)) {
        logger.info(`[FeedBuilder] Skipping fanout for post ${postId} — moderationStatus=${moderationStatus}`);
        return;
    }

    const visibility = normalizeVisibility(data.visibility);
    if (visibility === "everyone") return;

    if (await isFanoutThrottled(authorId)) {
        logger.warn(
            `[FeedBuilder] Fan-out throttled for author ${authorId} — post ${postId} skipped`
        );
        return;
    }

    const feedData = {
        postId,
        authorId,
        visibility,
        category: data.category ?? null,
        topicTag: data.topicTag ?? null,
        createdAt: data.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "private",
    };

    await writeFeedItems(postId, authorId, feedData);
});

export const onPostUpdateFeed = onDocumentUpdated("posts/{postId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const postId = event.params.postId;
    const authorId = (after.authorId ?? before?.authorId) as string | undefined;
    if (!authorId) return;

    // Safety OS: if post transitions to a blocked status, remove it from all feeds.
    const afterStatus = after.moderationStatus as string | undefined;
    const beforeStatus = before?.moderationStatus as string | undefined;
    if (afterStatus && BLOCKED_MODERATION_STATUSES.includes(afterStatus)) {
        if (!beforeStatus || !BLOCKED_MODERATION_STATUSES.includes(beforeStatus)) {
            logger.info(`[FeedBuilder] Removing post ${postId} from feeds — moderationStatus changed to ${afterStatus}`);
            await deleteFeedItems(postId, authorId);
        }
        return;
    }

    const beforeVisibility = normalizeVisibility(before?.visibility);
    const afterVisibility = normalizeVisibility(after.visibility);

    if (beforeVisibility !== "everyone" && afterVisibility === "everyone") {
        await deleteFeedItems(postId, authorId);
        return;
    }

    if (afterVisibility === "everyone") return;

    const feedData = {
        postId,
        authorId,
        visibility: afterVisibility,
        category: after.category ?? null,
        topicTag: after.topicTag ?? null,
        createdAt: after.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "private",
    };

    await writeFeedItems(postId, authorId, feedData);
});

export const onPostDeleteFeed = onDocumentDeleted("posts/{postId}", async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    const postId = event.params.postId;
    const authorId = data.authorId as string | undefined;
    if (!authorId) return;

    const visibility = normalizeVisibility(data.visibility);
    if (visibility === "everyone") return;

    await deleteFeedItems(postId, authorId);
});
