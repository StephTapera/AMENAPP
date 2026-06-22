import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-rtdb";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/database.rules.json");

const OWNER_UID = "rtdb-owner";
const OTHER_UID = "rtdb-other";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    database: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9000,
    },
  });
});

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function databaseAs(uid: string) {
  return testEnv.authenticatedContext(uid).database(`http://127.0.0.1:9000?ns=${PROJECT_ID}`);
}

describe("account RTDB owner isolation", () => {
  test("user can write own user profile path", async () => {
    await assertSucceeds(databaseAs(OWNER_UID).ref(`user_profiles/${OWNER_UID}`).set({
      displayName: "Owner",
      username: "owner",
    }));
  });

  test("user cannot write another user's profile path", async () => {
    await assertFails(databaseAs(OWNER_UID).ref(`user_profiles/${OTHER_UID}`).set({
      displayName: "Other",
      username: "other",
    }));
  });

  test("user can write own device/session-style online status", async () => {
    await assertSucceeds(databaseAs(OWNER_UID).ref(`online_status/${OWNER_UID}`).set({
      isOnline: true,
      lastSeen: Date.now(),
    }));
  });

  test("user cannot write another user's post index", async () => {
    await assertFails(databaseAs(OWNER_UID).ref(`user_posts/${OTHER_UID}`).set({
      postId: "p1",
      authorId: OTHER_UID,
      timestamp: Date.now(),
    }));
  });
});
