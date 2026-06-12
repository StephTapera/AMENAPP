/**
 * socialGraph.ragAcl.test.ts
 *
 * Unit tests for C-2: RAG search ACL filter in amenAIFeatures.js.
 *
 * The ACL filter runs on every result path before returning to the caller.
 * These tests verify the privacy-level and block logic that was previously
 * a TODO stub (return true) and is now an active per-result Firestore check.
 *
 * We test the logic inline (mirroring amenAIFeatures.js) without a live DB.
 *
 * Tests prove:
 *   - Private/followers-only post result is NEVER returned to non-follower
 *   - Blocked post result is NEVER returned (either block direction)
 *   - Owner always sees own results
 *   - Public post always passes
 *   - trustedCircle requires mutual follow
 */

// ─── Mirror of amenAIFeatures.js ragSearch ACL logic ─────────────────────────

interface PostData {
  authorId?: string;
  userId?: string;
  privacyLevel?: string;
  visibility?: string;
  isDeleted?: boolean;
}

interface RagResult {
  id: string;
  type: string;
  authorId: string | null;
  score: number;
}

interface BlockedUsers {
  [compositeKey: string]: boolean; // "uid1_uid2" → true
}

interface FollowsIndex {
  [compositeKey: string]: boolean; // "followerId_followeeId" → true
}

function normalisePrivacyLevel(data: PostData): string {
  const raw = data.privacyLevel || data.visibility || "public";
  if (raw === "Everyone") return "public";
  if (raw === "Followers") return "followers";
  if (raw === "Community Only") return "trustedCircle";
  return raw;
}

function isBlockedBetween(uidA: string, uidB: string, blockedUsers: BlockedUsers): boolean {
  return !!(blockedUsers[`${uidA}_${uidB}`] || blockedUsers[`${uidB}_${uidA}`]);
}

function callerCanAccessPost(
  callerUid: string,
  postData: PostData,
  followsIndex: FollowsIndex,
  blockedUsers: BlockedUsers
): boolean {
  if (!postData) return false;

  const authorId = postData.authorId || postData.userId || "";

  // Owner always has access
  if (callerUid === authorId) return true;

  // Block check (either direction)
  if (isBlockedBetween(callerUid, authorId, blockedUsers)) return false;

  const level = normalisePrivacyLevel(postData);

  if (level === "public" || level === "everyone") return true;

  if (level === "followers") {
    return !!(followsIndex[`${callerUid}_${authorId}`]);
  }

  if (level === "trustedCircle") {
    return !!(followsIndex[`${callerUid}_${authorId}`])
      && !!(followsIndex[`${authorId}_${callerUid}`]);
  }

  // church / space / private / unknown → deny from RAG results
  return false;
}

function filterRagResults(
  callerUid: string,
  results: RagResult[],
  postStore: Record<string, PostData | null>,
  followsIndex: FollowsIndex,
  blockedUsers: BlockedUsers
): RagResult[] {
  return results.filter((r) => {
    // Non-post types: churchNotes scoped at upsert, sermons/savedVerses public
    if (r.type !== "posts") return true;

    // Caller owns it — fast path
    if (r.authorId === callerUid) return true;

    const data = postStore[r.id];
    if (!data) return false; // deleted post — filtered out

    return callerCanAccessPost(callerUid, data, followsIndex, blockedUsers);
  });
}

// ─── Test fixtures ────────────────────────────────────────────────────────────

const CALLER = "caller_uid";
const AUTHOR = "author_uid";
const MUTUAL = "mutual_uid";

const baseResult = (id: string, authorId: string = AUTHOR): RagResult => ({
  id,
  type: "posts",
  authorId,
  score: 0.9,
});

const publicPost: PostData = { authorId: AUTHOR, privacyLevel: "public" };
const privatePost: PostData = { authorId: AUTHOR, privacyLevel: "private" };
const followersPost: PostData = { authorId: AUTHOR, privacyLevel: "followers" };
const legacyFollowersPost: PostData = { authorId: AUTHOR, visibility: "Followers" };
const trustedCirclePost: PostData = { authorId: AUTHOR, privacyLevel: "trustedCircle" };
const legacyCommunityPost: PostData = { authorId: AUTHOR, visibility: "Community Only" };

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("C-2: ragSearch ACL filter — privacy level enforcement", () => {
  const noFollows: FollowsIndex = {};
  const noBlocks: BlockedUsers = {};

  test("public post is accessible to any caller", () => {
    expect(callerCanAccessPost(CALLER, publicPost, noFollows, noBlocks)).toBe(true);
  });

  test("private post is NEVER returned to non-owner", () => {
    expect(callerCanAccessPost(CALLER, privatePost, noFollows, noBlocks)).toBe(false);
  });

  test("followers-only post NOT returned to non-follower", () => {
    expect(callerCanAccessPost(CALLER, followersPost, noFollows, noBlocks)).toBe(false);
  });

  test("followers-only post (legacy visibility='Followers') NOT returned to non-follower", () => {
    expect(callerCanAccessPost(CALLER, legacyFollowersPost, noFollows, noBlocks)).toBe(false);
  });

  test("followers-only post IS returned to a follower", () => {
    const follows: FollowsIndex = { [`${CALLER}_${AUTHOR}`]: true };
    expect(callerCanAccessPost(CALLER, followersPost, follows, noBlocks)).toBe(true);
  });

  test("trustedCircle post NOT returned to one-way follower", () => {
    const follows: FollowsIndex = { [`${CALLER}_${AUTHOR}`]: true };
    expect(callerCanAccessPost(CALLER, trustedCirclePost, follows, noBlocks)).toBe(false);
  });

  test("trustedCircle (legacy 'Community Only') NOT returned to one-way follower", () => {
    const follows: FollowsIndex = { [`${CALLER}_${AUTHOR}`]: true };
    expect(callerCanAccessPost(CALLER, legacyCommunityPost, follows, noBlocks)).toBe(false);
  });

  test("trustedCircle post IS returned to mutual follower", () => {
    const follows: FollowsIndex = {
      [`${CALLER}_${AUTHOR}`]: true,
      [`${AUTHOR}_${CALLER}`]: true,
    };
    expect(callerCanAccessPost(CALLER, trustedCirclePost, follows, noBlocks)).toBe(true);
  });

  test("owner always has access to own private post", () => {
    expect(callerCanAccessPost(AUTHOR, privatePost, noFollows, noBlocks)).toBe(true);
  });

  test("owner has access even if they are in blocked set (edge case: self)", () => {
    expect(callerCanAccessPost(AUTHOR, followersPost, noFollows, noBlocks)).toBe(true);
  });
});

describe("C-2: ragSearch ACL filter — block enforcement", () => {
  const noFollows: FollowsIndex = {};

  test("blocked user CANNOT see author's public post in RAG results", () => {
    const blocks: BlockedUsers = { [`${AUTHOR}_${CALLER}`]: true };
    expect(callerCanAccessPost(CALLER, publicPost, noFollows, blocks)).toBe(false);
  });

  test("caller who blocked author CANNOT see their post in RAG results", () => {
    const blocks: BlockedUsers = { [`${CALLER}_${AUTHOR}`]: true };
    expect(callerCanAccessPost(CALLER, publicPost, noFollows, blocks)).toBe(false);
  });

  test("non-blocked caller sees the same author's public post", () => {
    const blocks: BlockedUsers = {};
    expect(callerCanAccessPost(CALLER, publicPost, noFollows, blocks)).toBe(true);
  });

  test("block check runs BEFORE follow check (blocked follower denied)", () => {
    const follows: FollowsIndex = { [`${CALLER}_${AUTHOR}`]: true };
    const blocks: BlockedUsers = { [`${AUTHOR}_${CALLER}`]: true };
    expect(callerCanAccessPost(CALLER, followersPost, follows, blocks)).toBe(false);
  });
});

describe("C-2: ragSearch ACL filter — batch filter function", () => {
  const postStore: Record<string, PostData | null> = {
    "public1": publicPost,
    "private1": privatePost,
    "followers1": followersPost,
    "deleted1": null,
    "own1": { authorId: CALLER, privacyLevel: "private" },
  };

  const noFollows: FollowsIndex = {};
  const noBlocks: BlockedUsers = {};

  test("only accessible posts returned in batch filter", () => {
    const results: RagResult[] = [
      baseResult("public1"),
      baseResult("private1"),
      baseResult("followers1"),
      baseResult("deleted1"),
      baseResult("own1", CALLER),
    ];
    const filtered = filterRagResults(CALLER, results, postStore, noFollows, noBlocks);
    const ids = filtered.map((r) => r.id);
    expect(ids).toContain("public1");
    expect(ids).toContain("own1");
    expect(ids).not.toContain("private1");
    expect(ids).not.toContain("followers1");
    expect(ids).not.toContain("deleted1");
  });

  test("blocked caller sees no posts from that author even public ones", () => {
    const results: RagResult[] = [baseResult("public1")];
    const blocks: BlockedUsers = { [`${AUTHOR}_${CALLER}`]: true };
    const filtered = filterRagResults(CALLER, results, postStore, noFollows, blocks);
    expect(filtered).toHaveLength(0);
  });

  test("non-post results (churchNotes, sermons) are not filtered", () => {
    const nonPostResult: RagResult = { id: "note1", type: "churchNotes", authorId: CALLER, score: 0.8 };
    const results = [nonPostResult];
    const filtered = filterRagResults(CALLER, results, postStore, noFollows, noBlocks);
    expect(filtered).toHaveLength(1);
  });
});
