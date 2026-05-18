import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-trust-safety-launch";
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");
const STORAGE_RULES_PATH = path.resolve(__dirname, "../../AMENAPP/storage.rules");

const OWNER_UID = "trust-safety-owner";
const OTHER_UID = "trust-safety-other";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(STORAGE_RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", OWNER_UID), {
      uid: OWNER_UID,
      accountStatus: "active",
      emailVerified: true,
    });
    await setDoc(doc(db, "users", OTHER_UID), {
      uid: OTHER_UID,
      accountStatus: "active",
      emailVerified: true,
    });
    await setDoc(doc(db, "moderationCases", "case-1"), { caseId: "case-1" });
    await setDoc(doc(db, "trustSafetyEvents", "event-1"), { eventType: "report_submitted" });
    await setDoc(doc(db, "evidenceVault", "case-1"), { caseId: "case-1" });
    await setDoc(doc(db, "ncmecReadiness", "case-1"), { caseId: "case-1" });
  });
});

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid, {
    email_verified: true,
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

function storageAs(uid: string) {
  return testEnv.authenticatedContext(uid).storage("gs://amen-5e359.firebasestorage.app");
}

function uploadAs(uid: string, storagePath: string, contentType: string, size = 8): Promise<unknown> {
  return storageAs(uid)
    .ref(storagePath)
    .put(new Uint8Array(size), { contentType });
}

describe("Trust and Safety Firestore launch gates", () => {
  test("clients cannot bypass submitReport by writing report collections directly", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "reports", "direct-report"), {
      reporterId: OWNER_UID,
      reportedContentId: "post-1",
      reason: "csam",
      escalationTier: 1,
    }));

    await assertFails(setDoc(doc(dbAs(OWNER_UID), "userReports", "direct-user-report"), {
      reporterId: OWNER_UID,
      reportedUserId: OTHER_UID,
      reason: "csam",
      escalationTier: 1,
    }));
  });

  test.each([
    ["moderationCases", "case-1"],
    ["trustSafetyEvents", "event-1"],
    ["evidenceVault", "case-1"],
    ["ncmecReadiness", "case-1"],
  ])("non-admin clients cannot read or write %s", async (collectionName, documentId) => {
    await assertFails(getDoc(doc(dbAs(OWNER_UID), collectionName, documentId)));
    await assertFails(setDoc(doc(dbAs(OWNER_UID), collectionName, "client-write"), {
      unsafe: true,
    }));
  });
});

describe("Trust and Safety Storage launch gates", () => {
  test("raw media quarantine is owner-only", async () => {
    const rawPath = `mediaUploads/${OWNER_UID}/media-1/raw/photo.jpg`;
    await assertSucceeds(uploadAs(OWNER_UID, rawPath, "image/jpeg"));
    await assertFails(uploadAs(OTHER_UID, rawPath, "image/jpeg"));
  });

  test("processed media and legacy flat post image writes are server-owned", async () => {
    await assertFails(uploadAs(OWNER_UID, "mediaProcessed/media-1/full/photo.jpg", "image/jpeg"));
    await assertFails(uploadAs(OWNER_UID, "posts/images/photo.jpg", "image/jpeg"));
  });

  test("canonical post media requires owner-scoped path and safe content type", async () => {
    await assertSucceeds(uploadAs(OWNER_UID, `post_media/${OWNER_UID}/post-1/photo.jpg`, "image/jpeg"));
    await assertFails(uploadAs(OTHER_UID, `post_media/${OWNER_UID}/post-1/photo.jpg`, "image/jpeg"));
    await assertFails(uploadAs(OWNER_UID, `post_media/${OWNER_UID}/post-1/payload.svg`, "image/svg+xml"));
  });
});
