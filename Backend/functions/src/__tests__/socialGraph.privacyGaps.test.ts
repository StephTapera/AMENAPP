/**
 * socialGraph.privacyGaps.test.ts
 *
 * Tests for the 4 remaining open items from the 2026-06-12 Social Graph Privacy Audit:
 *
 *   GAP-A: Pending follow request must NOT be treated as an accepted follow
 *          in any permission check.
 *
 *   GAP-B: blockRelationshipCleanup — notifications revoked bidirectionally
 *          (both directions: blocker's inbox AND blocked user's inbox).
 *
 *   GAP-C: revokeNotificationsOnCommentDelete — notification docs for a
 *          soft-deleted comment must be removed from the post author's inbox.
 *
 *   GAP-D: reconcileFollowCounts — drift detected and corrected.
 *
 *   GAP-E: Private account follow → creates request doc, NOT a follow edge.
 *          (New gap from 2026-06-12 audit fix to createFollow.ts.)
 *
 *   GAP-F: buildPushText M-4 — commentText omitted from push body for
 *          non-public (limited) posts.
 *
 * All tests mirror the relevant logic inline without requiring a live emulator
 * (same pattern as socialGraph.rateLimit.test.ts and socialGraph.ragAcl.test.ts).
 *
 * See docs/SOCIAL_GRAPH_PRIVACY_AUDIT_2026-06-12.md for the original findings.
 */

// ─── GAP-A: Pending follow request ≠ accepted follow ─────────────────────────

interface FollowIndex { [key: string]: boolean }  // "followerId_followeeId" → true
interface FollowRequestStore { [key: string]: { status: string } } // "followerId" → request

/**
 * Mirror of aclHelper.ts isFollowing() + hasPendingFollowRequest()
 */
function isFollowing(followIndex: FollowIndex, followerId: string, followeeId: string): boolean {
    return followIndex[`${followerId}_${followeeId}`] === true;
}

function hasPendingRequest(requestStore: FollowRequestStore, requesterId: string): boolean {
    return requestStore[requesterId]?.status === "pending";
}

function canViewPrivatePost(
    followIndex: FollowIndex,
    requestStore: FollowRequestStore,
    viewerUid: string,
    authorUid: string
): boolean {
    if (viewerUid === authorUid) return true;
    // MUST check follows_index, NOT followRequests
    return isFollowing(followIndex, viewerUid, authorUid);
}

describe("GAP-A: Pending follow request is NOT an accepted follow", () => {
    const followIndex: FollowIndex = {};
    const requestStore: FollowRequestStore = { viewer123: { status: "pending" } };

    test("pending request does NOT grant canViewPrivatePost access", () => {
        const canView = canViewPrivatePost(followIndex, requestStore, "viewer123", "author456");
        expect(canView).toBe(false);
    });

    test("accepted follow (edge in follows_index) DOES grant access", () => {
        const indexWithEdge: FollowIndex = { "viewer123_author456": true };
        const canView = canViewPrivatePost(indexWithEdge, requestStore, "viewer123", "author456");
        expect(canView).toBe(true);
    });

    test("hasPendingRequest does not affect follow check — different code path", () => {
        expect(hasPendingRequest(requestStore, "viewer123")).toBe(true); // request exists
        // But follow check uses followIndex, which is empty
        expect(isFollowing(followIndex, "viewer123", "author456")).toBe(false);
    });

    test("owner always can view (own post, no follow check needed)", () => {
        const canView = canViewPrivatePost(followIndex, requestStore, "author456", "author456");
        expect(canView).toBe(true);
    });

    test("trustedCircle (mutuals): both directions required — pending is not mutual", () => {
        // pending from viewer→author exists, but author does NOT follow viewer
        const indexOnlyOneWay: FollowIndex = { "viewer123_author456": true };
        const isMutual =
            isFollowing(indexOnlyOneWay, "viewer123", "author456") &&
            isFollowing(indexOnlyOneWay, "author456", "viewer123");
        expect(isMutual).toBe(false);
    });
});

// ─── GAP-B: Notification revocation bidirectional on block ───────────────────

interface NotificationDoc {
    id: string;
    recipientId: string;
    actorId: string;
    postId?: string;
    commentId?: string;
}

interface NotificationStore {
    [userId: string]: NotificationDoc[];
}

/**
 * Mirror of blockRelationshipCleanup.ts revokeNotificationsOnBlock()
 */
function revokeNotificationsOnBlock(
    store: NotificationStore,
    blockerId: string,
    blockedId: string,
    limit = 100
): number {
    // Remove blockedId's notifications from blockerId's inbox
    const blockerInbox = store[blockerId] ?? [];
    const beforeBlocker = blockerInbox.length;
    store[blockerId] = blockerInbox.filter((n) => n.actorId !== blockedId).slice(0, limit);

    // Remove blockerId's notifications from blockedId's inbox
    const blockedInbox = store[blockedId] ?? [];
    const beforeBlocked = blockedInbox.length;
    store[blockedId] = blockedInbox.filter((n) => n.actorId !== blockerId).slice(0, limit);

    return (beforeBlocker - store[blockerId].length) + (beforeBlocked - store[blockedId].length);
}

describe("GAP-B: blockRelationshipCleanup — notification revocation is bidirectional", () => {
    function buildStore(): NotificationStore {
        return {
            alice: [
                { id: "n1", recipientId: "alice", actorId: "bob", commentId: "c1" },
                { id: "n2", recipientId: "alice", actorId: "bob", commentId: "c2" },
                { id: "n3", recipientId: "alice", actorId: "carol", commentId: "c3" },
            ],
            bob: [
                { id: "n4", recipientId: "bob", actorId: "alice", postId: "p1" },
                { id: "n5", recipientId: "bob", actorId: "carol", postId: "p2" },
            ],
        };
    }

    test("alice blocks bob: bob's notifications removed from alice's inbox", () => {
        const store = buildStore();
        revokeNotificationsOnBlock(store, "alice", "bob");
        const aliceIds = store.alice.map((n) => n.actorId);
        expect(aliceIds).not.toContain("bob");
        expect(aliceIds).toContain("carol"); // unrelated notification preserved
    });

    test("alice blocks bob: alice's notifications removed from bob's inbox", () => {
        const store = buildStore();
        revokeNotificationsOnBlock(store, "alice", "bob");
        const bobIds = store.bob.map((n) => n.actorId);
        expect(bobIds).not.toContain("alice");
        expect(bobIds).toContain("carol"); // unrelated preserved
    });

    test("bidirectional: both inboxes cleaned in the same operation", () => {
        const store = buildStore();
        const removed = revokeNotificationsOnBlock(store, "alice", "bob");
        expect(removed).toBe(3); // n1, n2 from alice's inbox + n4 from bob's
    });

    test("idempotent: running twice does not throw or over-delete", () => {
        const store = buildStore();
        revokeNotificationsOnBlock(store, "alice", "bob");
        expect(() => revokeNotificationsOnBlock(store, "alice", "bob")).not.toThrow();
    });

    test("unrelated users' notifications are not affected", () => {
        const store = buildStore();
        revokeNotificationsOnBlock(store, "alice", "bob");
        expect(store.bob.find((n) => n.actorId === "carol")).toBeDefined();
    });
});

// ─── GAP-C: Notification revocation on comment soft-delete ───────────────────

/**
 * Mirror of notificationRevocation.ts revokeNotificationsOnCommentDelete().
 * Only processes isDeleted: false → true transitions.
 */
function revokeNotificationsOnCommentDelete(
    store: NotificationStore,
    postAuthorId: string,
    commentId: string,
    before: { isDeleted?: boolean },
    after: { isDeleted?: boolean }
): number {
    // Only process false → true transition
    if (!after.isDeleted || before.isDeleted === true) return 0;

    const inbox = store[postAuthorId] ?? [];
    const before_count = inbox.length;
    store[postAuthorId] = inbox.filter(
        (n) => n.commentId !== commentId
    );
    return before_count - store[postAuthorId].length;
}

describe("GAP-C: revokeNotificationsOnCommentDelete", () => {
    function buildStore(): NotificationStore {
        return {
            author: [
                { id: "n1", recipientId: "author", actorId: "user1", commentId: "c_deleted" },
                { id: "n2", recipientId: "author", actorId: "user2", commentId: "c_other" },
                { id: "n3", recipientId: "author", actorId: "user3", commentId: "c_deleted" },
            ],
        };
    }

    test("soft-delete transition removes matching comment notifications", () => {
        const store = buildStore();
        const removed = revokeNotificationsOnCommentDelete(
            store, "author", "c_deleted",
            { isDeleted: false }, { isDeleted: true }
        );
        expect(removed).toBe(2);
        expect(store.author.every((n) => n.commentId !== "c_deleted")).toBe(true);
    });

    test("unrelated comment notifications are preserved", () => {
        const store = buildStore();
        revokeNotificationsOnCommentDelete(
            store, "author", "c_deleted",
            { isDeleted: false }, { isDeleted: true }
        );
        expect(store.author.some((n) => n.commentId === "c_other")).toBe(true);
    });

    test("already-deleted comment (before.isDeleted = true) → no-op", () => {
        const store = buildStore();
        const removed = revokeNotificationsOnCommentDelete(
            store, "author", "c_deleted",
            { isDeleted: true }, { isDeleted: true }
        );
        expect(removed).toBe(0);
    });

    test("comment becoming visible again (true → false) → no-op", () => {
        const store = buildStore();
        const removed = revokeNotificationsOnCommentDelete(
            store, "author", "c_deleted",
            { isDeleted: true }, { isDeleted: false }
        );
        expect(removed).toBe(0);
    });

    test("no notifications for this comment → no-op, no throw", () => {
        const store = buildStore();
        expect(() =>
            revokeNotificationsOnCommentDelete(
                store, "author", "c_not_in_store",
                { isDeleted: false }, { isDeleted: true }
            )
        ).not.toThrow();
    });
});

// ─── GAP-D: counterReconciliation — drift detection ──────────────────────────

interface UserRecord {
    uid: string;
    followersCount: number;
    followingCount: number;
}

interface FollowEdge {
    followerId: string;
    followingId: string;
}

/**
 * Mirror of counterReconciliation.ts recompute logic.
 * Returns list of users whose stored counts deviated from actual edge counts.
 */
function reconcileFollowCounts(
    users: UserRecord[],
    edges: FollowEdge[]
): Array<{ uid: string; storedFollowers: number; actualFollowers: number; storedFollowing: number; actualFollowing: number }> {
    const repaired = [];
    for (const user of users) {
        const actualFollowers = edges.filter((e) => e.followingId === user.uid).length;
        const actualFollowing = edges.filter((e) => e.followerId === user.uid).length;
        if (actualFollowers !== user.followersCount || actualFollowing !== user.followingCount) {
            repaired.push({
                uid: user.uid,
                storedFollowers: user.followersCount,
                actualFollowers,
                storedFollowing: user.followingCount,
                actualFollowing,
            });
        }
    }
    return repaired;
}

describe("GAP-D: reconcileFollowCounts — drift detection and repair", () => {
    const edges: FollowEdge[] = [
        { followerId: "alice", followingId: "bob" },
        { followerId: "alice", followingId: "carol" },
        { followerId: "bob", followingId: "alice" },
    ];

    test("no drift: returns empty list", () => {
        const users: UserRecord[] = [
            { uid: "alice", followersCount: 1, followingCount: 2 },
            { uid: "bob", followersCount: 1, followingCount: 1 },
            { uid: "carol", followersCount: 1, followingCount: 0 },
        ];
        expect(reconcileFollowCounts(users, edges)).toHaveLength(0);
    });

    test("drift detected: inflated followersCount is flagged", () => {
        const users: UserRecord[] = [
            { uid: "alice", followersCount: 99, followingCount: 2 }, // 99 is wrong; actual = 1
            { uid: "bob", followersCount: 1, followingCount: 1 },
            { uid: "carol", followersCount: 1, followingCount: 0 },
        ];
        const result = reconcileFollowCounts(users, edges);
        expect(result).toHaveLength(1);
        expect(result[0].uid).toBe("alice");
        expect(result[0].storedFollowers).toBe(99);
        expect(result[0].actualFollowers).toBe(1);
    });

    test("drift detected: deflated followingCount is flagged", () => {
        const users: UserRecord[] = [
            { uid: "alice", followersCount: 1, followingCount: 0 }, // 0 is wrong; actual = 2
            { uid: "bob", followersCount: 1, followingCount: 1 },
            { uid: "carol", followersCount: 1, followingCount: 0 },
        ];
        const result = reconcileFollowCounts(users, edges);
        expect(result).toHaveLength(1);
        expect(result[0].uid).toBe("alice");
        expect(result[0].storedFollowing).toBe(0);
        expect(result[0].actualFollowing).toBe(2);
    });

    test("multiple users drifted: all are returned", () => {
        const users: UserRecord[] = [
            { uid: "alice", followersCount: 0, followingCount: 0 }, // both wrong
            { uid: "bob", followersCount: 5, followingCount: 0 }, // followers wrong
            { uid: "carol", followersCount: 1, followingCount: 0 }, // correct
        ];
        const result = reconcileFollowCounts(users, edges);
        const uids = result.map((r) => r.uid);
        expect(uids).toContain("alice");
        expect(uids).toContain("bob");
        expect(uids).not.toContain("carol");
    });

    test("user with no follow edges has correct 0/0 counts", () => {
        const users: UserRecord[] = [
            { uid: "dave", followersCount: 0, followingCount: 0 },
        ];
        expect(reconcileFollowCounts(users, edges)).toHaveLength(0);
    });

    test("user with zero stored but actual > 0 is flagged (negative drift)", () => {
        const users: UserRecord[] = [
            { uid: "alice", followersCount: 0, followingCount: 0 },
        ];
        const result = reconcileFollowCounts(users, edges);
        expect(result[0].actualFollowers).toBe(1);
        expect(result[0].actualFollowing).toBe(2);
    });
});

// ─── GAP-E: createFollow private account → follow request, not edge ──────────

interface AccountState {
    isPrivate: boolean;
    ageTier?: string;
}

type FollowResult =
    | { type: "alreadyFollowing" }
    | { type: "requestSent"; guardianRouted: boolean }
    | { type: "requestAlreadySent" }
    | { type: "followed" };

function simulateCreateFollow(
    followerId: string,
    followingId: string,
    callerState: AccountState,
    targetState: AccountState,
    followIndex: FollowIndex,
    requestStore: FollowRequestStore
): FollowResult {
    if (followIndex[`${followerId}_${followingId}`]) {
        return { type: "alreadyFollowing" };
    }

    if (targetState.isPrivate) {
        if (requestStore[followerId]) {
            return { type: "requestAlreadySent" };
        }
        const isAdultToMinor =
            !callerState.ageTier?.startsWith("tier") &&
            (targetState.ageTier === "tierB" || targetState.ageTier === "tierC");
        requestStore[followerId] = { status: "pending" };
        return { type: "requestSent", guardianRouted: isAdultToMinor };
    }

    followIndex[`${followerId}_${followingId}`] = true;
    return { type: "followed" };
}

describe("GAP-E: createFollow — private account creates request, not edge", () => {
    test("public account follow creates follow edge", () => {
        const followIndex: FollowIndex = {};
        const requestStore: FollowRequestStore = {};
        const result = simulateCreateFollow(
            "viewer", "public_author",
            { isPrivate: false }, { isPrivate: false },
            followIndex, requestStore
        );
        expect(result.type).toBe("followed");
        expect(followIndex["viewer_public_author"]).toBe(true);
        expect(requestStore["viewer"]).toBeUndefined();
    });

    test("private account follow creates follow request, NOT edge", () => {
        const followIndex: FollowIndex = {};
        const requestStore: FollowRequestStore = {};
        const result = simulateCreateFollow(
            "viewer", "private_author",
            { isPrivate: false }, { isPrivate: true },
            followIndex, requestStore
        );
        expect(result.type).toBe("requestSent");
        expect(followIndex["viewer_private_author"]).toBeUndefined(); // NO edge created
        expect(requestStore["viewer"]).toEqual({ status: "pending" });
    });

    test("duplicate request to private account is idempotent", () => {
        const followIndex: FollowIndex = {};
        const requestStore: FollowRequestStore = { viewer: { status: "pending" } };
        const result = simulateCreateFollow(
            "viewer", "private_author",
            { isPrivate: false }, { isPrivate: true },
            followIndex, requestStore
        );
        expect(result.type).toBe("requestAlreadySent");
    });

    test("already following (edge exists) returns alreadyFollowing even for private", () => {
        const followIndex: FollowIndex = { "viewer_private_author": true };
        const requestStore: FollowRequestStore = {};
        const result = simulateCreateFollow(
            "viewer", "private_author",
            { isPrivate: false }, { isPrivate: true },
            followIndex, requestStore
        );
        expect(result.type).toBe("alreadyFollowing");
    });

    test("adult following minor (tierB) sets guardianRouted=true on request", () => {
        const followIndex: FollowIndex = {};
        const requestStore: FollowRequestStore = {};
        const result = simulateCreateFollow(
            "adult", "minor",
            { isPrivate: false, ageTier: undefined },
            { isPrivate: true, ageTier: "tierB" },
            followIndex, requestStore
        ) as { type: "requestSent"; guardianRouted: boolean };
        expect(result.type).toBe("requestSent");
        expect(result.guardianRouted).toBe(true);
    });

    test("teen following teen does NOT set guardianRouted", () => {
        const followIndex: FollowIndex = {};
        const requestStore: FollowRequestStore = {};
        const result = simulateCreateFollow(
            "teen1", "teen2",
            { isPrivate: false, ageTier: "tierB" },
            { isPrivate: true, ageTier: "tierB" },
            followIndex, requestStore
        ) as { type: "requestSent"; guardianRouted: boolean };
        expect(result.type).toBe("requestSent");
        expect(result.guardianRouted).toBe(false);
    });
});

// ─── GAP-F: buildPushText M-4 — commentText omitted for limited content ───────

enum LockScreenPrivacy { Full = "full", Minimal = "minimal", NameOnly = "nameOnly" }
type ContentPrivacy = "public" | "limited";

function buildPushTextMirror(
    type: "comment" | "reply" | "follow",
    actorName: string,
    lockScreen: LockScreenPrivacy,
    commentText?: string,
    contentPrivacy: ContentPrivacy = "public"
): { title: string; body: string } {
    if (lockScreen === LockScreenPrivacy.Minimal) {
        return { title: "AMEN", body: "You have a new notification" };
    }
    const includeCommentText = contentPrivacy !== "limited" && !!commentText;
    switch (type) {
        case "comment":
            return {
                title: "New Comment",
                body: includeCommentText
                    ? `${actorName} commented: ${commentText!.substring(0, 80)}`
                    : `${actorName} commented on your post`,
            };
        case "reply":
            return {
                title: "New Reply",
                body: includeCommentText
                    ? `${actorName} replied: ${commentText!.substring(0, 80)}`
                    : `${actorName} replied to your comment`,
            };
        default:
            return { title: "New Follower", body: `${actorName} started following you` };
    }
}

describe("GAP-F: buildPushText — M-4 commentText omitted for limited-privacy posts", () => {
    const text = "This is my comment text that should maybe be private";

    test("public post: commentText IS included in push body", () => {
        const result = buildPushTextMirror("comment", "Alice", LockScreenPrivacy.Full, text, "public");
        expect(result.body).toContain("Alice commented:");
        expect(result.body).toContain("This is my comment");
    });

    test("limited post (followers-only): commentText is NOT in push body", () => {
        const result = buildPushTextMirror("comment", "Alice", LockScreenPrivacy.Full, text, "limited");
        expect(result.body).toBe("Alice commented on your post");
        expect(result.body).not.toContain("This is my comment");
    });

    test("limited post reply: commentText is NOT in push body", () => {
        const result = buildPushTextMirror("reply", "Bob", LockScreenPrivacy.Full, text, "limited");
        expect(result.body).toBe("Bob replied to your comment");
        expect(result.body).not.toContain("This is my comment");
    });

    test("lockScreen=Minimal always returns generic message regardless of content privacy", () => {
        const result = buildPushTextMirror("comment", "Alice", LockScreenPrivacy.Minimal, text, "public");
        expect(result.body).toBe("You have a new notification");
    });

    test("no commentText: generic fallback regardless of contentPrivacy", () => {
        const result = buildPushTextMirror("comment", "Alice", LockScreenPrivacy.Full, undefined, "public");
        expect(result.body).toBe("Alice commented on your post");
    });

    test("limited post without commentText: generic message", () => {
        const result = buildPushTextMirror("comment", "Alice", LockScreenPrivacy.Full, undefined, "limited");
        expect(result.body).toBe("Alice commented on your post");
    });
});
