/**
 * aclHelper.ts — Shared ACL helper for Cloud Functions.
 *
 * WHY THIS EXISTS:
 *   §1 of the privacy model requires that every read path and every write path
 *   evaluate the SAME permission precedence from ONE shared implementation.
 *   Previously, permission checks were duplicated across multiple Cloud Functions
 *   with divergent logic. This module is the single server-side source of truth.
 *
 * Firestore Rules uses `canCommentOnPost()` and `isMutualConnectionWith()` helpers
 * that mirror this logic. Any change here must be reflected in firestore.rules and
 * vice versa.
 *
 * PRECEDENCE (from docs/privacy-model.md §1):
 *   1. Account deleted/suspended
 *   2. Block (bidirectional)
 *   3. Minor-safety policy
 *   4. Private account + not accepted follower
 *   5. Post-level audience
 *   6. Comment-permission setting
 *   7. Restrict
 *   8. Default allow
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

const db = () => admin.firestore();

// ─── Follow/Block Primitives ──────────────────────────────────────────────────

/**
 * Returns true if followerId has a follow edge to followeeId.
 * Uses the O(1) follows_index collection.
 */
export async function isFollowing(
    followerId: string,
    followeeId: string
): Promise<boolean> {
    if (!followerId || !followeeId || followerId === followeeId) return false;
    const doc = await db()
        .collection("follows_index")
        .doc(`${followerId}_${followeeId}`)
        .get();
    return doc.exists;
}

/**
 * Returns true if both users follow each other (mutual).
 * Never uses a stored boolean — always derived from live edges.
 */
export async function isMutual(uidA: string, uidB: string): Promise<boolean> {
    if (!uidA || !uidB || uidA === uidB) return false;
    const [ab, ba] = await Promise.all([
        db().collection("follows_index").doc(`${uidA}_${uidB}`).get(),
        db().collection("follows_index").doc(`${uidB}_${uidA}`).get(),
    ]);
    return ab.exists && ba.exists;
}

/**
 * Returns true if EITHER user has blocked the other.
 * Bidirectional: isBlocked(A, B) == isBlocked(B, A).
 */
export async function isBlocked(uidA: string, uidB: string): Promise<boolean> {
    if (!uidA || !uidB || uidA === uidB) return false;
    const [ab, ba] = await Promise.all([
        db().collection("blockedUsers").doc(`${uidA}_${uidB}`).get(),
        db().collection("blockedUsers").doc(`${uidB}_${uidA}`).get(),
    ]);
    return ab.exists || ba.exists;
}

/**
 * Returns true if the viewer has a pending follow request to the target
 * (i.e., target is private and request is outstanding, not yet accepted).
 * A pending request is NOT a follow — never treat it as one.
 */
export async function hasPendingFollowRequest(
    viewerUid: string,
    targetUid: string
): Promise<boolean> {
    const snap = await db()
        .collection("users")
        .doc(targetUid)
        .collection("followRequests")
        .where("requesterId", "==", viewerUid)
        .where("status", "==", "pending")
        .limit(1)
        .get();
    return !snap.empty;
}

// ─── Post ACL ─────────────────────────────────────────────────────────────────

/** Normalise visibility / privacyLevel field values from different schema versions. */
function resolvePrivacyLevel(data: admin.firestore.DocumentData): string {
    const pl = data.privacyLevel as string | undefined;
    const v = data.visibility as string | undefined;
    const level = pl ?? v ?? "public";
    // Normalise legacy capitalised values from PostsManager.Post.PostVisibility
    switch (level) {
        case "Everyone":
            return "public";
        case "Followers":
            return "followers";
        case "Community Only":
            return "trustedCircle";
        default:
            return level;
    }
}

/**
 * Returns true if viewerUid has read access to the post.
 *
 * Precedence:
 *   1. Block check (bidirectional) → deny
 *   2. Owner → allow
 *   3. Privacy level
 *
 * This is the TypeScript mirror of the Firestore Rules post read rule.
 * Both must be kept in sync.
 *
 * @param viewerUid  UID of the user requesting access
 * @param postId     Firestore document ID of the post
 * @param postData   Optional pre-fetched post data (avoids extra Firestore read)
 */
export async function canViewPost(
    viewerUid: string,
    postId: string,
    postData?: admin.firestore.DocumentData
): Promise<boolean> {
    const data =
        postData ??
        (await db().collection("posts").doc(postId).get()).data();
    if (!data) return false;

    const authorId = (data.authorId ?? data.userId ?? "") as string;

    // Owner always has access (unless account is suspended — checked separately)
    if (viewerUid === authorId) return true;

    // Block check precedes all other checks
    if (await isBlocked(viewerUid, authorId)) return false;

    const level = resolvePrivacyLevel(data);

    switch (level) {
        case "public":
            return true;

        case "followers":
            return isFollowing(viewerUid, authorId);

        case "trustedCircle":
            return isMutual(viewerUid, authorId);

        case "church": {
            // Church membership is validated via custom claim (churchId) — cannot
            // be checked here without the viewer's auth token. Defer to Firestore Rules.
            logger.warn(
                `[aclHelper.canViewPost] church-level post ${postId} — cannot validate church claim in CF context`
            );
            return false;
        }

        case "space": {
            const spaceId = (data.spaceId ?? "") as string;
            if (!spaceId) return false;
            const memberDoc = await db()
                .collection("spaces")
                .doc(spaceId)
                .collection("members")
                .doc(viewerUid)
                .get();
            return memberDoc.exists;
        }

        case "private":
        default:
            return false;
    }
}

// ─── Comment Permission ACL ───────────────────────────────────────────────────

/**
 * Returns true if viewerUid is allowed to create a comment on the given post.
 *
 * This is the TypeScript mirror of `canCommentOnPost(postId)` in firestore.rules.
 * Both must be kept in sync. See docs/privacy-model.md §6.
 *
 * Comment permission values stored in `commentPermissions` field:
 *   "Everyone"        — any non-blocked signed-in user
 *   "People I follow" — viewer must follow the post author
 *   "Mentioned only"  — mutual follow required (legacy mapping: stored as "Mentioned only"
 *                       by CreatePostView.mapToPostCommentPermissions for mutualsOnly)
 *   "Comments off"    — no one can comment
 *
 * @param viewerUid  UID attempting to comment
 * @param postId     Post document ID
 * @param postData   Optional pre-fetched post data
 */
export async function canCommentOnPost(
    viewerUid: string,
    postId: string,
    postData?: admin.firestore.DocumentData
): Promise<boolean> {
    const data =
        postData ??
        (await db().collection("posts").doc(postId).get()).data();
    if (!data) return false;

    const authorId = (data.authorId ?? data.userId ?? "") as string;
    const allowComments = data.allowComments as boolean | undefined;
    const perm = (data.commentPermissions as string | undefined) ?? "Everyone";

    // Comments disabled at the post level
    if (allowComments === false || perm === "Comments off") return false;

    // Owner can always comment when comments aren't off
    if (viewerUid === authorId) return true;

    // Block check (bidirectional) — must precede permission level checks
    if (await isBlocked(viewerUid, authorId)) return false;

    switch (perm) {
        case "Everyone":
            return true;

        case "People I follow":
            // Viewer must follow the author (author's follower-only comments).
            // UI label: "Only people who follow you" (people who follow the author).
            return isFollowing(viewerUid, authorId);

        case "Mentioned only":
            // Stored as proxy for mutuals-only via CreatePostView.mapToPostCommentPermissions.
            // Semantics: mutual follow required (both directions).
            return isMutual(viewerUid, authorId);

        default:
            // Unknown value or "Comments off" already handled above → deny (fail-closed)
            return false;
    }
}

// ─── Batch ACL helpers ────────────────────────────────────────────────────────

/**
 * Filter a list of post IDs to only those the viewer can access.
 * Batches Firestore reads for efficiency.
 */
export async function filterAccessiblePosts(
    viewerUid: string,
    postIds: string[]
): Promise<string[]> {
    if (postIds.length === 0) return [];

    const results = await Promise.allSettled(
        postIds.map(async (postId) => ({
            postId,
            accessible: await canViewPost(viewerUid, postId),
        }))
    );

    return results
        .filter(
            (r): r is PromiseFulfilledResult<{ postId: string; accessible: boolean }> =>
                r.status === "fulfilled"
        )
        .filter((r) => r.value.accessible)
        .map((r) => r.value.postId);
}

/**
 * Given an array of Pinecone search results (with `id` = Firestore post ID),
 * returns only the results the viewer is allowed to see.
 * Used by ragSearch to enforce ACL on testimony-embeddings.
 */
export async function filterAccessibleSearchResults<
    T extends { id: string; authorId?: string | null }
>(viewerUid: string, results: T[]): Promise<T[]> {
    if (results.length === 0) return [];

    const checks = await Promise.allSettled(
        results.map(async (result) => {
            // Fast path: viewer owns the content
            if (result.authorId === viewerUid) {
                return { result, accessible: true };
            }
            try {
                const accessible = await canViewPost(viewerUid, result.id);
                return { result, accessible };
            } catch (err) {
                logger.warn(
                    `[aclHelper.filterAccessibleSearchResults] Error checking post ${result.id}: ${(err as Error).message}`
                );
                return { result, accessible: false };
            }
        })
    );

    return checks
        .filter(
            (r): r is PromiseFulfilledResult<{ result: T; accessible: boolean }> =>
                r.status === "fulfilled"
        )
        .filter((r) => r.value.accessible)
        .map((r) => r.value.result);
}
