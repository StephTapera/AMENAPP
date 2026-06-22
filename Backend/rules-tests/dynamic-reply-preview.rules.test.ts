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

const PROJECT_ID = "amen-rules-test-dynamic-preview";
// P1-5: tests target the deployed artifact (firestore.deploy.rules); see
// jest.globalSetup.ts for the regeneration step.
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "owner-uid";
const VIEWER_UID = "viewer-uid";
const POST_ID = "post-dynamic-preview-1";

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
    await setDoc(doc(db, "users", OWNER_UID), { isPrivate: false });
    await setDoc(doc(db, "users", VIEWER_UID), { isPrivate: false });
    await setDoc(doc(db, "posts", POST_ID), {
      authorId: OWNER_UID,
      visibility: "everyone",
      content: "public post",
      category: "general",
      isRemoved: false,
    });
    await setDoc(doc(db, "posts", POST_ID, "dynamicReplyPreviews", "preview-1"), {
      id: "preview-1",
      type: "topReply",
      previewText: "safe preview",
      sourceCommentIds: ["c1"],
    });
  });
});

afterAll(async () => {
  if (testEnv) {
    // Hardened: testEnv is undefined if beforeAll failed (e.g.
    // emulator not running). The real root cause is reported by
    // jest.globalSetup.ts.
    await testEnv.cleanup();
  }
});

describe("dynamic reply preview rules", () => {
  test("public preview readable -> post private -> previous viewer cannot read preview", async () => {
    const viewerDb = testEnv.authenticatedContext(VIEWER_UID).firestore();
    await assertSucceeds(getDoc(doc(viewerDb, "posts", POST_ID, "dynamicReplyPreviews", "preview-1")));

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "posts", POST_ID), { visibility: "private" });
    });

    await assertFails(getDoc(doc(viewerDb, "posts", POST_ID, "dynamicReplyPreviews", "preview-1")));
  });

  test("client write to dynamicReplyPreviews denied", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(setDoc(doc(ownerDb, "posts", POST_ID, "dynamicReplyPreviews", "preview-client"), {
      id: "preview-client",
      type: "topReply",
      previewText: "client write",
    }));
  });

  test("client write to dynamicReplyPreviewCandidates denied", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(ownerDb, "posts", POST_ID), {
      dynamicReplyPreviewCandidates: [{ id: "x", previewText: "client-generated" }],
    }));
  });

  test("preview meta unreadable to clients", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "posts", POST_ID, "dynamicReplyPreviewMeta", "state"), {
        lastRefreshedAt: new Date(),
      });
    });
    const viewerDb = testEnv.authenticatedContext(VIEWER_UID).firestore();
    await assertFails(getDoc(doc(viewerDb, "posts", POST_ID, "dynamicReplyPreviewMeta", "state")));
  });
});
