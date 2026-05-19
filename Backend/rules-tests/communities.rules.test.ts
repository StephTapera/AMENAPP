import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator, storageEmulator, databaseEmulator, databaseUrl } from "./emulatorConfig";

// P1-2 + P1-Phase-F + P1-1: Rules tests for the Communities / Saved
// Communities / Stripe-customer-mapping surfaces locked down in this
// remediation. Targets the deployed rules artifact.

const PROJECT_ID = "amen-rules-test-communities";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "owner-uid";
const OTHER_UID = "other-uid";
const MEMBER_UID = "member-uid";
const ADMIN_UID = "admin-uid";

const COMMUNITY_ID = "community-1";
const PRIVATE_COMMUNITY_ID = "community-private-1";
const ARK_COMMUNITY_ID = "ark-1";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: firestoreEmulator.host,
      port: firestoreEmulator.port,
    },
  });
});

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Seed both communities and arkCommunities with realistic shapes so
    // the update-denial tests have something to update against.
    await setDoc(doc(db, "users", OWNER_UID), {
      uid: OWNER_UID, accountStatus: "active", deletionStatus: "none",
    });
    await setDoc(doc(db, "users", OTHER_UID), {
      uid: OTHER_UID, accountStatus: "active", deletionStatus: "none",
    });
    await setDoc(doc(db, "users", MEMBER_UID), {
      uid: MEMBER_UID, accountStatus: "active", deletionStatus: "none",
    });

    await setDoc(doc(db, "communities", COMMUNITY_ID), {
      name: "Public Community",
      description: "A public community",
      creatorId: OWNER_UID,
      adminIds: [OWNER_UID],
      memberCount: 1,
      postCount: 0,
      isPrivate: false,
      // Seed with values DIFFERENT from what the deny-tests will attempt to
      // write, so Firestore rules `diff()` actually flags the server-owned
      // field as changed and the rule's hasAny() guard fires.
      moderationStatus: "pending",
      safetyStatus: "pending",
      rankingScore: 0,
      isOfficial: false,
      isArchived: false,
      isDeleted: false,
      createdAt: new Date().toISOString(),
    });

    await setDoc(doc(db, "communities", PRIVATE_COMMUNITY_ID), {
      name: "Private Community",
      description: "Members only",
      creatorId: OWNER_UID,
      adminIds: [OWNER_UID],
      memberCount: 1,
      postCount: 0,
      isPrivate: true,
      moderationStatus: "approved",
      safetyStatus: "approved",
      createdAt: new Date().toISOString(),
    });
    await setDoc(
      doc(db, `communities/${PRIVATE_COMMUNITY_ID}/members/${MEMBER_UID}`),
      { userId: MEMBER_UID, joinedAt: new Date().toISOString() }
    );

    await setDoc(doc(db, "arkCommunities", ARK_COMMUNITY_ID), {
      name: "Ark Public",
      description: "Ark legacy",
      creatorId: OWNER_UID,
      adminIds: [OWNER_UID],
      memberCount: 1,
      postCount: 0,
      moderationStatus: "approved",
      safetyStatus: "approved",
      createdAt: new Date().toISOString(),
    });

    // Stripe mapping fixture for read-denial test.
    await setDoc(doc(db, "stripeCustomers/cus_test"), {
      uid: OWNER_UID,
      provider: "stripe",
      createdAt: new Date().toISOString(),
    });
  });
});

// ── /communities create (P1-2) ────────────────────────────────────────────────

describe("/communities create — direct client write is denied (P1-2)", () => {
  test("any signed-in user cannot create a community directly", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(setDoc(doc(db, "communities/new-cov"), {
      name: "Forged",
      description: "Should be denied",
      creatorId: OTHER_UID,
    }));
  });

  test("admin custom claim cannot bypass via direct create either", async () => {
    const db = testEnv.authenticatedContext(ADMIN_UID, { admin: true }).firestore();
    await assertFails(setDoc(doc(db, "communities/admin-cov"), {
      name: "Forged",
      description: "Should be denied",
      creatorId: ADMIN_UID,
    }));
  });
});

// ── /communities update server-owned fields (P1-2) ────────────────────────────

describe("/communities update — server-owned fields are denied (P1-2)", () => {
  test("creator cannot mutate adminIds via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      adminIds: [OWNER_UID, OTHER_UID],
    }));
  });

  test("creator cannot mutate memberCount via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      memberCount: 9999,
    }));
  });

  test("creator cannot mutate postCount via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      postCount: 9999,
    }));
  });

  test("creator cannot mutate rankingScore via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      rankingScore: 1.0,
    }));
  });

  test("creator cannot mutate safetyStatus via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      safetyStatus: "approved",
    }));
  });

  test("creator cannot mutate moderationStatus via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      moderationStatus: "approved",
    }));
  });

  test("creator cannot mutate isOfficial via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      isOfficial: true,
    }));
  });

  test("creator cannot mutate isArchived via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      isArchived: true,
    }));
  });

  test("creator cannot mutate isDeleted via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      isDeleted: true,
    }));
  });

  test("creator can still mutate safe fields (name/description)", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      name: "Renamed",
      description: "Updated description",
    }));
  });

  test("non-admin user cannot update at all", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(updateDoc(doc(db, `communities/${COMMUNITY_ID}`), {
      name: "Hijacked",
    }));
  });
});

// ── /communities private-read gate ───────────────────────────────────────────

describe("/communities private-community read gate (P1-2)", () => {
  test("non-member cannot read a private community", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, `communities/${PRIVATE_COMMUNITY_ID}`)));
  });

  test("member can read a private community", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, `communities/${PRIVATE_COMMUNITY_ID}`)));
  });

  test("creator can read a private community", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, `communities/${PRIVATE_COMMUNITY_ID}`)));
  });

  test("non-member cannot read posts of a private community", async () => {
    // Seed a post first (rules disabled).
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `communities/${PRIVATE_COMMUNITY_ID}/posts/p1`),
        { authorId: OWNER_UID, content: "secret" }
      );
    });
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, `communities/${PRIVATE_COMMUNITY_ID}/posts/p1`)));
  });
});

// ── /arkCommunities lockdown (P1-7) ──────────────────────────────────────────

describe("/arkCommunities — direct client create denied + server-owned fields denied (P1-7)", () => {
  test("any signed-in user cannot create an ark community directly", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(setDoc(doc(db, "arkCommunities/new-ark"), {
      name: "Forged",
      description: "Should be denied",
      creatorId: OTHER_UID,
    }));
  });

  test("creator cannot mutate ark adminIds via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `arkCommunities/${ARK_COMMUNITY_ID}`), {
      adminIds: [OWNER_UID, OTHER_UID],
    }));
  });

  test("creator cannot mutate ark memberCount via client update", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, `arkCommunities/${ARK_COMMUNITY_ID}`), {
      memberCount: 9999,
    }));
  });
});

// ── users/{uid}/savedCommunities owner isolation (P1-Phase-F) ────────────────

describe("users/{uid}/savedCommunities — owner-isolated, callable-only writes (P1-Phase-F)", () => {
  test("owner can read own savedCommunities", async () => {
    // Pre-seed under rules-disabled (callable would normally write).
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${OWNER_UID}/savedCommunities/covenant_${COMMUNITY_ID}`),
        { communityId: COMMUNITY_ID, communityType: "covenant", saved: true }
      );
    });
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(getDoc(
      doc(db, `users/${OWNER_UID}/savedCommunities/covenant_${COMMUNITY_ID}`)
    ));
  });

  test("another user cannot read someone else's savedCommunities", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${OWNER_UID}/savedCommunities/covenant_${COMMUNITY_ID}`),
        { communityId: COMMUNITY_ID, communityType: "covenant", saved: true }
      );
    });
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(
      doc(db, `users/${OWNER_UID}/savedCommunities/covenant_${COMMUNITY_ID}`)
    ));
  });

  test("user cannot write to their own savedCommunities directly — callable only", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(setDoc(
      doc(db, `users/${OWNER_UID}/savedCommunities/covenant_forge`),
      { communityId: "forge", communityType: "covenant", saved: true }
    ));
  });

  test("user cannot write to ANOTHER user's savedCommunities", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(setDoc(
      doc(db, `users/${OWNER_UID}/savedCommunities/covenant_forge`),
      { communityId: "forge", communityType: "covenant", saved: true }
    ));
  });
});

// ── stripeCustomers — server-only (P1-1) ─────────────────────────────────────

describe("stripeCustomers — server-only access (P1-1)", () => {
  test("authenticated user cannot read stripeCustomers", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(getDoc(doc(db, "stripeCustomers/cus_test")));
  });

  test("admin custom claim cannot read stripeCustomers from client", async () => {
    const db = testEnv.authenticatedContext(ADMIN_UID, { admin: true }).firestore();
    await assertFails(getDoc(doc(db, "stripeCustomers/cus_test")));
  });

  test("authenticated user cannot write to stripeCustomers", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(setDoc(doc(db, "stripeCustomers/cus_forge"), {
      uid: OWNER_UID,
      provider: "stripe",
    }));
  });
});
