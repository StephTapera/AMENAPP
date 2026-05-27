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

const PROJECT_ID = "amen-rules-test-media-captions";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");
const OWNER_UID = "media-caption-owner";
const OTHER_UID = "media-caption-other";
const POST_ID = "media-caption-post";

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
    await setDoc(doc(db, "users", OWNER_UID), {
      isPrivate: false,
      accountStatus: "active",
    });
    await setDoc(doc(db, "users", OTHER_UID), {
      isPrivate: false,
      accountStatus: "active",
    });
    await setDoc(doc(db, "posts", POST_ID), {
      authorId: OWNER_UID,
      authorName: "Owner",
      content: "legacy post",
      category: "general",
      visibility: "everyone",
      status: "publishing",
      moderationStatus: "not_required",
      publicationVisibility: "public",
      amenCount: 0,
      lightbulbCount: 0,
      commentCount: 0,
      repostCount: 0,
    });
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

function validPostCreate(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    authorId: OWNER_UID,
    authorName: "Owner",
    content: "photo post",
    category: "general",
    status: "moderating",
    moderationStatus: "pending",
    publicationVisibility: "private_pending",
    amenCount: 0,
    lightbulbCount: 0,
    commentCount: 0,
    repostCount: 0,
    ...extra,
  };
}

describe("per-media caption security rules", () => {
  test("legacy post without media captions remains readable", async () => {
    const viewerDb = testEnv.authenticatedContext(OTHER_UID, {
      email_verified: true,
      firebase: { sign_in_provider: "apple.com" },
    }).firestore();

    await assertSucceeds(getDoc(doc(viewerDb, "posts", POST_ID)));
  });

  test("valid owner post create without moderation outcome fields is allowed", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID, {
      email_verified: true,
      firebase: { sign_in_provider: "apple.com" },
    }).firestore();

    await assertSucceeds(setDoc(doc(ownerDb, "posts", "valid-caption-create"), validPostCreate()));
  });

  test("client create cannot set mediaCaptionModeration", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID, {
      email_verified: true,
      firebase: { sign_in_provider: "apple.com" },
    }).firestore();

    await assertFails(setDoc(doc(ownerDb, "posts", "bad-caption-create"), validPostCreate({
      mediaCaptionModeration: {
        status: "approved",
        rejectedCount: 0,
      },
    })));
  });

  test("owner update cannot set captionModeration outcome field", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID, {
      email_verified: true,
      firebase: { sign_in_provider: "apple.com" },
    }).firestore();

    await assertFails(updateDoc(doc(ownerDb, "posts", POST_ID), {
      captionModeration: { status: "approved" },
    }));
  });

  test("non-owner edit denied", async () => {
    const otherDb = testEnv.authenticatedContext(OTHER_UID, {
      email_verified: true,
      firebase: { sign_in_provider: "apple.com" },
    }).firestore();

    await assertFails(updateDoc(doc(otherDb, "posts", POST_ID), {
      content: "malicious edit",
    }));
  });
});
