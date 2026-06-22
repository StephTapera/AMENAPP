import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator, storageEmulator, databaseEmulator, databaseUrl } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-storage";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/storage.rules");

const OWNER_UID = "storage-owner";
const OTHER_UID = "storage-other";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: storageEmulator.host,
      port: storageEmulator.port,
    },
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

function storageAs(uid: string) {
  return testEnv.authenticatedContext(uid).storage("gs://amen-5e359.firebasestorage.app");
}

function uploadProfileImage(uid: string, path: string, data: Uint8Array, contentType: string): Promise<unknown> {
  const uploadTask = storageAs(uid).ref(path).put(data, { contentType });
  return new Promise((resolve, reject) => {
    uploadTask.then(resolve, reject);
  });
}

describe("account storage profile image rules", () => {
  test("owner can upload valid profile image to own path", async () => {
    await assertSucceeds(uploadProfileImage(
      OWNER_UID,
      `profile_images/${OWNER_UID}/avatar.jpg`,
      new Uint8Array([1, 2, 3]),
      "image/jpeg"
    ));
  });

  test("user cannot upload profile image to another user's path", async () => {
    await assertFails(uploadProfileImage(
      OWNER_UID,
      `profile_images/${OTHER_UID}/avatar.jpg`,
      new Uint8Array([1, 2, 3]),
      "image/jpeg"
    ));
  });

  test("invalid profile image content type is rejected", async () => {
    await assertFails(uploadProfileImage(
      OWNER_UID,
      `profile_images/${OWNER_UID}/avatar.svg`,
      new Uint8Array([1, 2, 3]),
      "image/svg+xml"
    ));
  });

  test("oversized profile image is rejected", async () => {
    await assertFails(uploadProfileImage(
      OWNER_UID,
      `profile_images/${OWNER_UID}/large.jpg`,
      new Uint8Array(6 * 1024 * 1024),
      "image/jpeg"
    ));
  });
});
