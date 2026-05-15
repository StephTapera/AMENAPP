import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-account-lifecycle";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore 18.rules");

const OWNER_UID = "owner-account";
const OTHER_UID = "other-account";
const POST_ID = "account-post";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", OWNER_UID), {
      uid: OWNER_UID,
      username: "owner",
      displayName: "Owner User",
      isPrivate: false,
      accountStatus: "active",
      deletionStatus: "none",
      hasCompletedOnboarding: false,
      twoFactorEnabled: false,
      email: "owner@example.com",
    });
    await setDoc(doc(db, "users", OTHER_UID), {
      uid: OTHER_UID,
      username: "other",
      displayName: "Other User",
      isPrivate: false,
      accountStatus: "active",
      deletionStatus: "none",
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid, {
    email_verified: true,
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

async function seedUserPatch(uid: string, patch: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "users", uid), patch);
  });
}

describe("account lifecycle user document rules", () => {
  test("owner can read own private account document", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID)));
  });

  test("other user cannot read user doc containing private account/security fields", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "users", OWNER_UID)));
  });

  test("other user can read public-safe user doc", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "users", OTHER_UID)));
  });

  test("owner can update safe profile fields", async () => {
    await assertSucceeds(updateDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID), {
      displayName: "Updated Owner",
      bio: "safe profile update",
    }));
  });

  test.each([
    "role",
    "isAdmin",
    "isModerator",
    "accountStatus",
    "isDeactivated",
    "deactivatedAt",
    "deactivationExpiresAt",
    "deactivationReason",
    "deletionStatus",
    "deletedAt",
    "isDeleting",
    "emailVerified",
    "phoneVerified",
    "ageVerified",
    "twoFactorEnabled",
    "twoFactorVerified",
    "twoFactorSession",
    "backupCodes",
    "hasCompletedOnboarding",
    "onboardingCompletedAt",
    "termsAcceptedAt",
    "privacyAcceptedAt",
    "username",
    "usernameLowercase",
  ])("owner cannot update protected field %s", async (field) => {
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID), {
      [field]: field.endsWith("At") ? new Date() : true,
    }));
  });

  test("owner cannot delete users/{uid}", async () => {
    await assertFails(deleteDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID)));
  });
});

describe("usernameLookup and server-owned security paths", () => {
  test("client cannot create, update, or delete usernameLookup", async () => {
    const ref = doc(dbAs(OWNER_UID), "usernameLookup", "owner");
    await assertFails(setDoc(ref, { uid: OWNER_UID, username: "owner", usernameLowercase: "owner" }));

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "usernameLookup", "owner"), {
        uid: OWNER_UID,
        username: "owner",
        usernameLowercase: "owner",
      });
    });

    await assertFails(updateDoc(ref, { uid: OTHER_UID }));
    await assertFails(deleteDoc(ref));
  });

  test("client cannot read or write userSecurity backup codes or 2FA state", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "userSecurity", OWNER_UID), {
        backupCodes: [{ codeHash: "hash", used: false }],
        session2FAActive: true,
      });
    });

    await assertFails(getDoc(doc(dbAs(OWNER_UID), "userSecurity", OWNER_UID)));
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "userSecurity", OWNER_UID), {
      backupCodes: ["plaintext"],
      session2FAActive: true,
    }, { merge: true }));
  });

  test("client cannot create, complete, or delete deletionRequests", async () => {
    const ref = doc(dbAs(OWNER_UID), "deletionRequests", OWNER_UID);
    await assertFails(setDoc(ref, { userId: OWNER_UID, requestedAt: new Date(), reason: "test" }));

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "deletionRequests", OWNER_UID), {
        userId: OWNER_UID,
        status: "requested",
      });
    });

    await assertFails(updateDoc(ref, { status: "complete" }));
    await assertFails(deleteDoc(ref));
  });
});

describe("active account write gates", () => {
  const postPayload = {
    authorId: OWNER_UID,
    authorName: "Owner User",
    content: "A safe account lifecycle post",
    category: "general",
    amenCount: 0,
    lightbulbCount: 0,
    commentCount: 0,
    repostCount: 0,
    status: "draft",
  };

  test("active user can create a key content post", async () => {
    await assertSucceeds(setDoc(doc(dbAs(OWNER_UID), "posts", POST_ID), postPayload));
  });

  test("deactivated user cannot create key content", async () => {
    await seedUserPatch(OWNER_UID, {
      accountStatus: "deactivated",
      isDeactivated: true,
    });
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "posts", POST_ID), postPayload));
  });

  test("deleting user cannot create key content", async () => {
    await seedUserPatch(OWNER_UID, {
      accountStatus: "deleting",
      deletionStatus: "requested",
      isDeleting: true,
    });
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "posts", POST_ID), postPayload));
  });

  test("client cannot mark onboarding complete directly", async () => {
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID), {
      hasCompletedOnboarding: true,
      onboardingCompletedAt: new Date(),
    }));
  });

  test("owner can register own device token but cannot write another user's token", async () => {
    await assertSucceeds(setDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID, "deviceTokens", "device-a"), {
      tokenHash: "hash",
      enabled: true,
      platform: "ios",
    }));
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "users", OTHER_UID, "deviceTokens", "device-b"), {
      tokenHash: "hash",
      enabled: true,
      platform: "ios",
    }));
  });
});
