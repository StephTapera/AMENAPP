/**
 * spaces_rules.test.js
 * AMEN Spaces — Firestore Security Rules Tests
 *
 * Tests all 9 security scenarios from AGENT_A_data_rules.md Step 3.
 *
 * Run with:
 *   firebase emulators:exec --only firestore \
 *     "node --experimental-vm-modules node_modules/.bin/jest spaces-spec/spaces_rules.test.js"
 *
 * Requires @firebase/rules-unit-testing >= 3.x and firebase-admin.
 */

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

const PROJECT_ID = "amen-spaces-rules-test";
const RULES_PATH = resolve(__dirname, "../firestore.rules");

let testEnv;

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeSpaceId() { return "space_" + Math.random().toString(36).slice(2); }
function makeUserId() { return "user_" + Math.random().toString(36).slice(2); }
function makeCommunityId() { return "com_" + Math.random().toString(36).slice(2); }

/**
 * Seed a Space document (accessPolicy: "free" or "oneTime"/"recurring").
 * Uses the admin context (bypasses rules).
 */
async function seedSpace(spaceId, accessPolicy, communityId) {
  const admin = testEnv.withSecurityRulesDisabled();
  await admin.firestore().collection("spaces").doc(spaceId).set({
    communityId,
    type: "chat",
    title: "Test Space",
    accessPolicy,
    createdBy: "system",
    createdAt: new Date(),
    sharedWith: [],
    priceConfig: accessPolicy === "free" ? null : { amountCents: 999, currency: "usd" },
  });
}

/**
 * Seed a space member document.
 */
async function seedSpaceMember(spaceId, userId, opts = {}) {
  const admin = testEnv.withSecurityRulesDisabled();
  await admin.firestore()
    .collection("spaces").doc(spaceId)
    .collection("members").doc(userId).set({
      role: opts.role || "member",
      homeCommunityId: opts.homeCommunityId || "",
      access: opts.access || "granted",
      joinedAt: new Date(),
    });
}

/**
 * Seed an entitlement document (flat top-level).
 */
async function seedEntitlement(userId, spaceId, status) {
  const admin = testEnv.withSecurityRulesDisabled();
  await admin.firestore()
    .collection("entitlements").doc(`${userId}_${spaceId}`).set({
      userId,
      spaceId,
      status,
      source: "purchase",
      stripeSubId: "sub_test123",
      expiresAt: null,
      updatedAt: new Date(),
    });
}

/**
 * Seed a message document.
 */
async function seedMessage(spaceId, threadId, messageId, authorId) {
  const admin = testEnv.withSecurityRulesDisabled();
  await admin.firestore()
    .collection("spaces").doc(spaceId)
    .collection("threads").doc(threadId)
    .collection("messages").doc(messageId).set({
      authorId,
      body: "Test message",
      createdAt: new Date(),
      reactions: {},
      attachments: [],
      status: "active",
    });
}

/**
 * Seed an amenCommunity link document.
 */
async function seedCommunityLink(fromCommunityId, linkId, status, otherCommunityId) {
  const admin = testEnv.withSecurityRulesDisabled();
  await admin.firestore()
    .collection("amenCommunities").doc(fromCommunityId)
    .collection("links").doc(linkId).set({
      otherCommunityId,
      status,
      scope: "test",
      createdBy: "system",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
}

// ── Test setup ─────────────────────────────────────────────────────────────────

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, "utf8"),
      host: "localhost",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("Scenario 1: Free Space — authenticated member reads", () => {
  test("ALLOW: member with access=granted reads message in free space", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "free", communityId);
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertSucceeds(msgRef.get());
  });

  test("DENY: unauthenticated user cannot read message in free space", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "free", communityId);
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.unauthenticatedContext();
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertFails(msgRef.get());
  });
});

describe("Scenario 2: Paid Space — no entitlement (deny)", () => {
  test("DENY: user without entitlement cannot read message in paid space", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "oneTime", communityId);
    // User is a member but has no entitlement row at all
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertFails(msgRef.get());
  });
});

describe("Scenario 3: Paid Space — active entitlement (allow)", () => {
  test("ALLOW: user with active entitlement reads message in paid space", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "oneTime", communityId);
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedEntitlement(userId, spaceId, "active");
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertSucceeds(msgRef.get());
  });
});

describe("Scenario 4: Paid Space — grace entitlement (allow)", () => {
  test("ALLOW: user with grace entitlement reads message in paid space", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "recurring", communityId);
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedEntitlement(userId, spaceId, "grace");
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertSucceeds(msgRef.get());
  });
});

describe("Scenario 5: Paid Space — expired entitlement (deny)", () => {
  test("DENY: user with expired entitlement cannot read message", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "recurring", communityId);
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedEntitlement(userId, spaceId, "expired");
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertFails(msgRef.get());
  });
});

describe("Scenario 6: External member via active link (allow)", () => {
  test("ALLOW: external member with active link reads message in free space", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const owningCommunityId = makeCommunityId();
    const homeCommunityId = makeCommunityId();
    const linkId = `${homeCommunityId}_${owningCommunityId}`;
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "free", owningCommunityId);
    // External member — homeCommunityId is set
    await seedSpaceMember(spaceId, userId, {
      access: "granted",
      homeCommunityId,
    });
    // Active link from home community to owning community
    await seedCommunityLink(homeCommunityId, linkId, "active", owningCommunityId);
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertSucceeds(msgRef.get());
  });
});

describe("Scenario 7: External member via revoked link (deny)", () => {
  test("DENY: external member with revoked link cannot read message", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const owningCommunityId = makeCommunityId();
    const homeCommunityId = makeCommunityId();
    const linkId = `${homeCommunityId}_${owningCommunityId}`;
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "free", owningCommunityId);
    // External member with access = "none" (set by revokeSpaceLinkAccess function)
    await seedSpaceMember(spaceId, userId, {
      access: "none",
      homeCommunityId,
    });
    // Revoked link
    await seedCommunityLink(homeCommunityId, linkId, "revoked", owningCommunityId);
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertFails(msgRef.get());
  });
});

describe("Scenario 8: Admin/owner bypass", () => {
  test("ALLOW: space admin can read message in paid space without entitlement", async () => {
    const spaceId = makeSpaceId();
    const adminId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "oneTime", communityId);
    // Admin role — no entitlement needed
    await seedSpaceMember(spaceId, adminId, { role: "admin", access: "granted" });
    await seedMessage(spaceId, threadId, messageId, adminId);

    // Also set up amenCommunity admin record for isAmenSpaceAdmin helper
    const admin = testEnv.withSecurityRulesDisabled();
    await admin.firestore()
      .collection("amenCommunities").doc(communityId)
      .collection("members").doc(adminId).set({ role: "admin", joinedAt: new Date() });

    const ctx = testEnv.authenticatedContext(adminId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertSucceeds(msgRef.get());
  });
});

describe("Scenario 9: Entitlement writes — client blocked", () => {
  test("DENY: client cannot write an entitlement directly", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();

    const ctx = testEnv.authenticatedContext(userId);
    const entRef = ctx.firestore()
      .collection("entitlements").doc(`${userId}_${spaceId}`);

    await assertFails(entRef.set({
      userId,
      spaceId,
      status: "active",
      source: "grant",
      updatedAt: new Date(),
    }));
  });

  test("ALLOW: user can read their own entitlement", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();

    await seedEntitlement(userId, spaceId, "active");

    const ctx = testEnv.authenticatedContext(userId);
    const entRef = ctx.firestore()
      .collection("entitlements").doc(`${userId}_${spaceId}`);

    await assertSucceeds(entRef.get());
  });

  test("DENY: user cannot read another user's entitlement", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const otherUserId = makeUserId();

    await seedEntitlement(userId, spaceId, "active");

    const ctx = testEnv.authenticatedContext(otherUserId);
    const entRef = ctx.firestore()
      .collection("entitlements").doc(`${userId}_${spaceId}`);

    await assertFails(entRef.get());
  });
});

describe("Hard delete prevention", () => {
  test("DENY: client cannot delete a message", async () => {
    const spaceId = makeSpaceId();
    const userId = makeUserId();
    const communityId = makeCommunityId();
    const threadId = "thread1";
    const messageId = "msg1";

    await seedSpace(spaceId, "free", communityId);
    await seedSpaceMember(spaceId, userId, { access: "granted" });
    await seedMessage(spaceId, threadId, messageId, userId);

    const ctx = testEnv.authenticatedContext(userId);
    const msgRef = ctx.firestore()
      .collection("spaces").doc(spaceId)
      .collection("threads").doc(threadId)
      .collection("messages").doc(messageId);

    await assertFails(msgRef.delete());
  });
});

describe("amenCommunities rules", () => {
  test("ALLOW: signed-in user reads community profile", async () => {
    const communityId = makeCommunityId();
    const userId = makeUserId();

    const adminCtx = testEnv.withSecurityRulesDisabled();
    await adminCtx.firestore().collection("amenCommunities").doc(communityId).set({
      name: "Test Community",
      handle: "testcom",
      ownerUserId: "owner1",
      createdAt: new Date(),
    });

    const ctx = testEnv.authenticatedContext(userId);
    await assertSucceeds(
      ctx.firestore().collection("amenCommunities").doc(communityId).get()
    );
  });

  test("DENY: client cannot create an amenCommunity", async () => {
    const communityId = makeCommunityId();
    const userId = makeUserId();
    const ctx = testEnv.authenticatedContext(userId);

    await assertFails(
      ctx.firestore().collection("amenCommunities").doc(communityId).set({
        name: "Hacked Community",
        ownerUserId: userId,
        createdAt: new Date(),
      })
    );
  });
});
