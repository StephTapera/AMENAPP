/**
 * rules.spec.js
 *
 * Firestore Rules unit tests for the social graph & privacy audit items
 * from SOCIAL_GRAPH_PRIVACY_AUDIT_2026-06-12.md (C-1, C-3).
 *
 * Mirrors the exact helper functions and rule conditions from firestore.rules
 * using plain JavaScript (no emulator required), following the pattern
 * established in safety-rules.test.js.
 *
 * Coverage:
 *   C-3 isEffectivelyPublic() / isFollowersOnlyPost() / isTrustedCirclePost()
 *     - followers-only post (privacyLevel field)
 *     - followers-only post (visibility field, legacy)
 *     - missing privacyLevel + visibility="" defaults to public-readable
 *     - missing privacyLevel + visibility="Followers" is followers-only (NOT public)
 *     - trustedCircle post requires mutual follow
 *   C-1 canCommentOnPost() helper logic
 *     - "Everyone" commentPermissions → any non-blocked signed-in user
 *     - "People I follow" → viewer must follow the author
 *     - "Mentioned only" → mutual follow required
 *     - "Comments off" → no one can comment
 *     - blocked user cannot comment regardless of permission level
 *     - allowComments: false overrides permission level
 *     - public post → stranger can comment (regression check)
 */

"use strict";

// ─── Mirrors of Firestore rules helper functions ──────────────────────────────

function isSignedIn(auth) {
  return auth != null;
}

function isOwner(auth, uid) {
  return isSignedIn(auth) && auth.uid === uid;
}

function isUnderMinimum(auth) {
  const tier = (auth && auth.token && auth.token.ageTier) || "";
  return isSignedIn(auth) && ["blocked", "under_minimum"].includes(tier);
}

/**
 * Mirrors isEffectivelyPublic() from firestore.rules (2026-06-12).
 * Returns true if either privacyLevel == 'public', OR privacyLevel is missing
 * and visibility is 'Everyone', 'everyone', or '' (empty).
 */
function isEffectivelyPublic(data) {
  const pl = data.privacyLevel || "";
  const v = data.visibility || "";
  return pl === "public"
    || (pl === "" && (v === "Everyone" || v === "everyone" || v === ""));
}

/**
 * Mirrors isFollowersOnlyPost() from firestore.rules.
 */
function isFollowersOnlyPost(data) {
  const pl = data.privacyLevel || "";
  const v = data.visibility || "";
  return pl === "followers"
    || (pl === "" && (v === "Followers" || v === "followers"));
}

/**
 * Mirrors isTrustedCirclePost() from firestore.rules.
 */
function isTrustedCirclePost(data) {
  const pl = data.privacyLevel || "";
  const v = data.visibility || "";
  return pl === "trustedCircle"
    || (pl === "" && (v === "Community Only" || v === "community"));
}

/**
 * Mirrors isMutualConnectionWith(): both follow edges must exist.
 * followsIndex is a Set<string> of "followerId_followeeId" strings.
 */
function isMutualConnectionWith(auth, authorUid, followsIndex) {
  if (!isSignedIn(auth)) return false;
  const ab = followsIndex.has(`${auth.uid}_${authorUid}`);
  const ba = followsIndex.has(`${authorUid}_${auth.uid}`);
  return ab && ba;
}

/**
 * Mirrors commentPermLevel() from firestore.rules.
 */
function commentPermLevel(postData) {
  return postData.commentPermissions || "Everyone";
}

/**
 * Mirrors commentBlockedCheck(): either direction blocked.
 * blockedUsers is a Set<string> of "uid1_uid2" strings.
 */
function commentBlockedCheck(auth, authorId, blockedUsers) {
  return blockedUsers.has(`${authorId}_${auth.uid}`)
    || blockedUsers.has(`${auth.uid}_${authorId}`);
}

/**
 * Mirrors canCommentOnPost() from firestore.rules.
 * followsIndex: Set<"followerId_followeeId">
 * blockedUsers: Set<"uid1_uid2">
 */
function canCommentOnPost(callerAuth, postData, followsIndex, blockedUsers) {
  if (!isSignedIn(callerAuth) || isUnderMinimum(callerAuth)) return false;

  const authorId = postData.authorId || "";
  const allowComments = postData.allowComments !== undefined ? postData.allowComments : true;
  const perm = commentPermLevel(postData);

  if (!allowComments || perm === "Comments off") return false;

  // Owner can always comment
  if (callerAuth.uid === authorId) return true;

  // Block check (bidirectional)
  if (commentBlockedCheck(callerAuth, authorId, blockedUsers)) return false;

  switch (perm) {
    case "Everyone":
      return true;
    case "People I follow":
      return followsIndex.has(`${callerAuth.uid}_${authorId}`);
    case "Mentioned only":
      return followsIndex.has(`${callerAuth.uid}_${authorId}`)
        && followsIndex.has(`${authorId}_${callerAuth.uid}`);
    default:
      return false;
  }
}

/**
 * Mirrors post read rule: can the caller read a post?
 */
function canReadPost(callerAuth, postData, followsIndex) {
  const authorId = postData.authorId || "";

  // Public — readable by anyone (unauthenticated ok per OPEN-5)
  if (isEffectivelyPublic(postData)) return true;

  if (!isSignedIn(callerAuth)) return false;

  // Owner always has access
  if (isOwner(callerAuth, authorId)) return true;

  // Followers-only
  if (isFollowersOnlyPost(postData)) {
    return followsIndex.has(`${callerAuth.uid}_${authorId}`);
  }

  // TrustedCircle: mutual follow required
  if (isTrustedCirclePost(postData)) {
    return isMutualConnectionWith(callerAuth, authorId, followsIndex);
  }

  // Private: owner only (already handled above)
  if ((postData.privacyLevel === "private") || (postData.visibility === "private")) {
    return false;
  }

  return false;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const AUTHOR = "author_uid";
const VIEWER = "viewer_uid";
const STRANGER = "stranger_uid";
const BLOCKED = "blocked_uid";

// Auth objects
const authorAuth = { uid: AUTHOR, token: {} };
const viewerAuth = { uid: VIEWER, token: {} };
const strangerAuth = { uid: STRANGER, token: {} };
const blockedAuth = { uid: BLOCKED, token: {} };
const minorAuth = { uid: "minor_uid", token: { ageTier: "blocked" } };
const unauthenticated = null;

describe("C-3: isEffectivelyPublic / isFollowersOnlyPost / isTrustedCirclePost", () => {
  describe("isEffectivelyPublic", () => {
    test("privacyLevel='public' → public", () => {
      expect(isEffectivelyPublic({ privacyLevel: "public" })).toBe(true);
    });
    test("visibility='Everyone' (no privacyLevel) → public", () => {
      expect(isEffectivelyPublic({ visibility: "Everyone" })).toBe(true);
    });
    test("visibility='everyone' → public", () => {
      expect(isEffectivelyPublic({ visibility: "everyone" })).toBe(true);
    });
    test("both fields missing → public (empty string default)", () => {
      expect(isEffectivelyPublic({})).toBe(true);
    });
    test("visibility='Followers' (no privacyLevel) → NOT public", () => {
      expect(isEffectivelyPublic({ visibility: "Followers" })).toBe(false);
    });
    test("privacyLevel='followers' → NOT public", () => {
      expect(isEffectivelyPublic({ privacyLevel: "followers" })).toBe(false);
    });
    test("privacyLevel='trustedCircle' → NOT public", () => {
      expect(isEffectivelyPublic({ privacyLevel: "trustedCircle" })).toBe(false);
    });
    test("privacyLevel='private' → NOT public", () => {
      expect(isEffectivelyPublic({ privacyLevel: "private" })).toBe(false);
    });
  });

  describe("isFollowersOnlyPost", () => {
    test("privacyLevel='followers' → followers-only", () => {
      expect(isFollowersOnlyPost({ privacyLevel: "followers" })).toBe(true);
    });
    test("visibility='Followers' (no privacyLevel) → followers-only", () => {
      expect(isFollowersOnlyPost({ visibility: "Followers" })).toBe(true);
    });
    test("visibility='followers' (lowercase) → followers-only", () => {
      expect(isFollowersOnlyPost({ visibility: "followers" })).toBe(true);
    });
    test("visibility='Everyone' → NOT followers-only", () => {
      expect(isFollowersOnlyPost({ visibility: "Everyone" })).toBe(false);
    });
    test("privacyLevel='public' → NOT followers-only", () => {
      expect(isFollowersOnlyPost({ privacyLevel: "public" })).toBe(false);
    });
  });

  describe("isTrustedCirclePost", () => {
    test("privacyLevel='trustedCircle' → trustedCircle", () => {
      expect(isTrustedCirclePost({ privacyLevel: "trustedCircle" })).toBe(true);
    });
    test("visibility='Community Only' → trustedCircle", () => {
      expect(isTrustedCirclePost({ visibility: "Community Only" })).toBe(true);
    });
    test("visibility='community' → trustedCircle", () => {
      expect(isTrustedCirclePost({ visibility: "community" })).toBe(true);
    });
    test("visibility='Everyone' → NOT trustedCircle", () => {
      expect(isTrustedCirclePost({ visibility: "Everyone" })).toBe(false);
    });
  });
});

describe("C-3: post read rule with follower/mutual checks", () => {
  const followersOnlyPost = { authorId: AUTHOR, privacyLevel: "followers" };
  const legacyFollowersPost = { authorId: AUTHOR, visibility: "Followers" };
  const trustedCirclePost = { authorId: AUTHOR, privacyLevel: "trustedCircle" };
  const publicPost = { authorId: AUTHOR, privacyLevel: "public" };

  const followerIndex = new Set([`${VIEWER}_${AUTHOR}`]);            // VIEWER follows AUTHOR
  const mutualIndex = new Set([`${VIEWER}_${AUTHOR}`, `${AUTHOR}_${VIEWER}`]); // mutual
  const emptyIndex = new Set();

  describe("followers-only (privacyLevel='followers')", () => {
    test("non-follower CANNOT read", () => {
      expect(canReadPost(strangerAuth, followersOnlyPost, emptyIndex)).toBe(false);
    });
    test("follower CAN read", () => {
      expect(canReadPost(viewerAuth, followersOnlyPost, followerIndex)).toBe(true);
    });
    test("owner CAN read", () => {
      expect(canReadPost(authorAuth, followersOnlyPost, emptyIndex)).toBe(true);
    });
    test("unauthenticated CANNOT read", () => {
      expect(canReadPost(unauthenticated, followersOnlyPost, emptyIndex)).toBe(false);
    });
  });

  describe("followers-only (legacy visibility='Followers', no privacyLevel)", () => {
    test("non-follower CANNOT read — legacy schema is NOT world-readable", () => {
      expect(canReadPost(strangerAuth, legacyFollowersPost, emptyIndex)).toBe(false);
    });
    test("follower CAN read legacy followers-only post", () => {
      expect(canReadPost(viewerAuth, legacyFollowersPost, followerIndex)).toBe(true);
    });
  });

  describe("trustedCircle (mutual follow required)", () => {
    test("one-way follower CANNOT read trustedCircle post", () => {
      expect(canReadPost(viewerAuth, trustedCirclePost, followerIndex)).toBe(false);
    });
    test("mutual follower CAN read trustedCircle post", () => {
      expect(canReadPost(viewerAuth, trustedCirclePost, mutualIndex)).toBe(true);
    });
    test("non-follower CANNOT read trustedCircle post", () => {
      expect(canReadPost(strangerAuth, trustedCirclePost, emptyIndex)).toBe(false);
    });
  });

  describe("public post — no regression", () => {
    test("unauthenticated CAN read public post", () => {
      expect(canReadPost(unauthenticated, publicPost, emptyIndex)).toBe(true);
    });
    test("stranger CAN read public post", () => {
      expect(canReadPost(strangerAuth, publicPost, emptyIndex)).toBe(true);
    });
  });
});

describe("C-1: canCommentOnPost (TOCTOU enforcement)", () => {
  const everyonePost = { authorId: AUTHOR, allowComments: true, commentPermissions: "Everyone" };
  const followersCommentPost = { authorId: AUTHOR, allowComments: true, commentPermissions: "People I follow" };
  const mutualsCommentPost = { authorId: AUTHOR, allowComments: true, commentPermissions: "Mentioned only" };
  const commentsOffPost = { authorId: AUTHOR, allowComments: true, commentPermissions: "Comments off" };
  const allowCommentsOffPost = { authorId: AUTHOR, allowComments: false, commentPermissions: "Everyone" };

  const followerIndex = new Set([`${VIEWER}_${AUTHOR}`]);
  const mutualIndex = new Set([`${VIEWER}_${AUTHOR}`, `${AUTHOR}_${VIEWER}`]);
  const emptyIndex = new Set();
  const blockedSet = new Set([`${AUTHOR}_${BLOCKED}`, `${BLOCKED}_${AUTHOR}`]);
  const emptyBlocked = new Set();

  describe("'Everyone' — any non-blocked signed-in user", () => {
    test("stranger CAN comment on Everyone post", () => {
      expect(canCommentOnPost(strangerAuth, everyonePost, emptyIndex, emptyBlocked)).toBe(true);
    });
    test("owner CAN comment", () => {
      expect(canCommentOnPost(authorAuth, everyonePost, emptyIndex, emptyBlocked)).toBe(true);
    });
    test("blocked user CANNOT comment even on Everyone post", () => {
      expect(canCommentOnPost(blockedAuth, everyonePost, emptyIndex, blockedSet)).toBe(false);
    });
    test("under-minimum CANNOT comment", () => {
      expect(canCommentOnPost(minorAuth, everyonePost, emptyIndex, emptyBlocked)).toBe(false);
    });
  });

  describe("'People I follow' — follower-only comments", () => {
    test("non-follower CANNOT comment", () => {
      expect(canCommentOnPost(strangerAuth, followersCommentPost, emptyIndex, emptyBlocked)).toBe(false);
    });
    test("follower CAN comment", () => {
      expect(canCommentOnPost(viewerAuth, followersCommentPost, followerIndex, emptyBlocked)).toBe(true);
    });
    test("blocked follower CANNOT comment", () => {
      const blockerSet = new Set([`${AUTHOR}_${VIEWER}`]);
      expect(canCommentOnPost(viewerAuth, followersCommentPost, followerIndex, blockerSet)).toBe(false);
    });
    test("owner CAN always comment", () => {
      expect(canCommentOnPost(authorAuth, followersCommentPost, emptyIndex, emptyBlocked)).toBe(true);
    });
  });

  describe("'Mentioned only' — mutuals-only comments", () => {
    test("one-way follower CANNOT comment (not mutual)", () => {
      expect(canCommentOnPost(viewerAuth, mutualsCommentPost, followerIndex, emptyBlocked)).toBe(false);
    });
    test("mutual follower CAN comment", () => {
      expect(canCommentOnPost(viewerAuth, mutualsCommentPost, mutualIndex, emptyBlocked)).toBe(true);
    });
    test("non-follower CANNOT comment", () => {
      expect(canCommentOnPost(strangerAuth, mutualsCommentPost, emptyIndex, emptyBlocked)).toBe(false);
    });
  });

  describe("'Comments off'", () => {
    test("no one can comment — not even the author", () => {
      expect(canCommentOnPost(authorAuth, commentsOffPost, emptyIndex, emptyBlocked)).toBe(false);
    });
    test("no one can comment — not even a follower", () => {
      expect(canCommentOnPost(viewerAuth, commentsOffPost, mutualIndex, emptyBlocked)).toBe(false);
    });
  });

  describe("allowComments: false — global off switch", () => {
    test("overrides Everyone permission — no one can comment", () => {
      expect(canCommentOnPost(strangerAuth, allowCommentsOffPost, emptyIndex, emptyBlocked)).toBe(false);
    });
    test("overrides even for the author", () => {
      expect(canCommentOnPost(authorAuth, allowCommentsOffPost, emptyIndex, emptyBlocked)).toBe(false);
    });
  });

  describe("blocked user — C-1 bidirectional block check", () => {
    test("blocked user CANNOT comment on followers-only post", () => {
      const postWithFollowerComment = { ...followersCommentPost };
      const blockedFollowerIndex = new Set([`${BLOCKED}_${AUTHOR}`]); // blocked also follows
      const bSet = new Set([`${AUTHOR}_${BLOCKED}`]);
      expect(canCommentOnPost(blockedAuth, postWithFollowerComment, blockedFollowerIndex, bSet)).toBe(false);
    });
    test("user who blocked the author CANNOT comment", () => {
      const callerBlockedAuthor = new Set([`${VIEWER}_${AUTHOR}`]);
      expect(canCommentOnPost(viewerAuth, everyonePost, emptyIndex, callerBlockedAuthor)).toBe(false);
    });
  });
});
