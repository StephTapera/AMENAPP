import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-security-closers";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const MINOR_A = "minor-a";
const MINOR_B = "minor-b";
const ADULT_A = "adult-a";
const ADULT_B = "adult-b";
const AUTHOR_UID = "author-uid";

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

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", MINOR_A), { uid: MINOR_A, ageTier: "teen" });
    await setDoc(doc(db, "users", MINOR_B), { uid: MINOR_B, ageTier: "teen" });
    await setDoc(doc(db, "users", ADULT_A), { uid: ADULT_A, ageTier: "tierD" });
    await setDoc(doc(db, "users", ADULT_B), { uid: ADULT_B, ageTier: "tierD" });
    await setDoc(doc(db, "posts", "post-1"), {
      authorId: AUTHOR_UID,
      privacyLevel: "public",
      provenance: "server",
      isDeleted: false,
    });
    await setDoc(doc(db, "discernmentChecks", "shared-check"), {
      createdBy: AUTHOR_UID,
      visibility: "shared",
      sourceRef: { threadId: "thread-1" },
      deletedAt: null,
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

function dbAs(uid: string, ageTier = "tierD") {
  return testEnv.authenticatedContext(uid, {
    role: ageTier === "teen" ? "minor" : "member",
    ageTier,
    email_verified: true,
  }).firestore();
}

async function seedFollowIndex(fromUid: string, toUid: string) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "follows_index", `${fromUid}_${toUid}`), {
      followerId: fromUid,
      followingId: toUid,
      status: "active",
    });
  });
}

function conversationPayload(participantUids: string[]) {
  return {
    participantUids,
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

describe("isMinorSafeDM matrix", () => {
  test("minor-minor with mutual follows_index entries is allowed", async () => {
    await seedFollowIndex(MINOR_A, MINOR_B);
    await seedFollowIndex(MINOR_B, MINOR_A);

    await assertSucceeds(setDoc(
      doc(dbAs(MINOR_A, "teen"), "conversations", "minor-mutual"),
      conversationPayload([MINOR_A, MINOR_B]),
    ));
  });

  test("minor-minor without mutual follows_index entries is denied", async () => {
    await assertFails(setDoc(
      doc(dbAs(MINOR_A, "teen"), "conversations", "minor-no-relationship"),
      conversationPayload([MINOR_A, MINOR_B]),
    ));
  });

  test("adult-to-minor without the required relationship is denied", async () => {
    await assertFails(setDoc(
      doc(dbAs(ADULT_A), "conversations", "adult-to-minor-denied"),
      conversationPayload([ADULT_A, MINOR_A]),
    ));
  });

  test("adult-adult remains unaffected by minor DM gate", async () => {
    await assertSucceeds(setDoc(
      doc(dbAs(ADULT_A), "conversations", "adult-adult"),
      conversationPayload([ADULT_A, ADULT_B]),
    ));
  });

  test("asymmetric follows_index is denied because policy requires mutual follows", async () => {
    await seedFollowIndex(MINOR_A, MINOR_B);

    await assertFails(setDoc(
      doc(dbAs(MINOR_A, "teen"), "conversations", "minor-asymmetric"),
      conversationPayload([MINOR_A, MINOR_B]),
    ));
  });
});

describe("follows_index data reality", () => {
  test("current backend and iOS follow writers populate follows_index", () => {
    const backendCreateFollow = fs.readFileSync(path.resolve(__dirname, "../functions/src/createFollow.ts"), "utf8");
    const iosFollowService = fs.readFileSync(path.resolve(__dirname, "../../AMENAPP/FollowService.swift"), "utf8");

    expect(backendCreateFollow).toContain("follows_index");
    expect(backendCreateFollow).toContain("batch.set(indexDocRef");
    expect(iosFollowService).toContain("follows_index");
    expect(iosFollowService).toContain("setData");
  });
});

describe("provenanceUnchanged wiring", () => {
  test("update attempting provenance mutation is denied", async () => {
    await assertFails(updateDoc(doc(dbAs(AUTHOR_UID), "posts", "post-1"), {
      provenance: "client-mutated",
    }));
  });

  test("legitimate owner update that leaves provenance unchanged is allowed", async () => {
    await assertSucceeds(updateDoc(doc(dbAs(AUTHOR_UID), "posts", "post-1"), {
      caption: "safe edit",
    }));
  });
});

describe("validSoftDelete wiring", () => {
  test("soft-delete touching disallowed fields is denied", async () => {
    await assertFails(updateDoc(doc(dbAs("moderator", "tierD"), "posts", "post-1"), {
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
      deletedBy: "moderator",
      caption: "not allowed in a soft-delete update",
    }));
  });

  test("clean moderator soft-delete is allowed", async () => {
    const moderatorDb = testEnv.authenticatedContext("moderator", {
      role: "moderator",
      ageTier: "tierD",
      orgId: "org-1",
      churchId: "church-1",
    }).firestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "posts", "post-1"), {
        orgId: "org-1",
        churchId: "church-1",
      });
    });

    await assertSucceeds(updateDoc(doc(moderatorDb, "posts", "post-1"), {
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
      deletedBy: "moderator",
    }));
  });
});

describe("discernment-read tightening", () => {
  test("shared discernment check is not readable by a non-creator through sourceRef alone", async () => {
    await assertFails(getDoc(doc(dbAs(ADULT_A), "discernmentChecks", "shared-check")));
  });

  test("discernment check creator can read own shared check", async () => {
    await assertSucceeds(getDoc(doc(dbAs(AUTHOR_UID), "discernmentChecks", "shared-check")));
  });
});
