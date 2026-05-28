/**
 * Firestore Security Rules — Access Pass tests
 *
 * Verifies that direct client access to access pass collections is blocked.
 * All mutations must go through callable Cloud Functions (enforced server-side).
 *
 * Prerequisites:
 *   1. cd Backend/rules-tests && npm install
 *   2. firebase emulators:start --only firestore   (separate terminal)
 *   3. npm test
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

let testEnv: RulesTestEnvironment;

const OWNER_UID  = "user-owner-001";
const OTHER_UID  = "user-other-002";
const PASS_ID    = "pass-abc-123";
const REQUEST_ID = "req-xyz-456";
const CHECKIN_ID = "chk-789";

const fakePassDoc = () => ({
  passId: PASS_ID,
  targetType: "space",
  targetId: "space-1",
  status: "active",
  createdBy: OWNER_UID,
});

const fakeRequestDoc = () => ({
  requestId: REQUEST_ID,
  accessPassId: PASS_ID,
  requesterUid: OWNER_UID,
  status: "pending",
});

const fakeCheckInDoc = () => ({
  checkInId: CHECKIN_ID,
  accessPassId: PASS_ID,
  userId: OWNER_UID,
  checkedInAt: Date.now(),
});

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
    await setDoc(doc(db, "accessPasses", PASS_ID), fakePassDoc());
    await setDoc(doc(db, "accessRequests", REQUEST_ID), fakeRequestDoc());
    await setDoc(doc(db, "activeCheckIns", CHECKIN_ID), fakeCheckInDoc());
    await setDoc(doc(db, "accessPassRateLimits", OWNER_UID), { count: 3 });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─────────────────────────────────────────────
// accessPasses — deny all direct access
// ─────────────────────────────────────────────

describe("accessPasses — authenticated user", () => {
  test("cannot read own pass", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(getDoc(doc(db, "accessPasses", PASS_ID)));
  });

  test("cannot read another user's pass", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, "accessPasses", PASS_ID)));
  });

  test("cannot create a pass", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(setDoc(doc(db, "accessPasses", "new-pass"), fakePassDoc()));
  });

  test("cannot update a pass", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, "accessPasses", PASS_ID), { status: "revoked" }));
  });

  test("cannot delete a pass", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(deleteDoc(doc(db, "accessPasses", PASS_ID)));
  });
});

describe("accessPasses/events — authenticated user", () => {
  test("cannot read events subcollection", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(getDoc(doc(db, "accessPasses", PASS_ID, "events", "evt-1")));
  });

  test("cannot write to events subcollection", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, "accessPasses", PASS_ID, "events", "evt-new"), { type: "check_in" })
    );
  });
});

describe("accessPasses — unauthenticated", () => {
  test("cannot read a pass", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "accessPasses", PASS_ID)));
  });
});

// ─────────────────────────────────────────────
// accessRequests — requester reads own; no writes
// ─────────────────────────────────────────────

describe("accessRequests — requester", () => {
  test("can read own request", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, "accessRequests", REQUEST_ID)));
  });

  test("cannot create a request directly", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, "accessRequests", "new-req"), { ...fakeRequestDoc(), requestId: "new-req" })
    );
  });

  test("cannot update a request", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(updateDoc(doc(db, "accessRequests", REQUEST_ID), { status: "approved" }));
  });

  test("cannot delete a request", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(deleteDoc(doc(db, "accessRequests", REQUEST_ID)));
  });
});

describe("accessRequests — other user", () => {
  test("cannot read another user's request", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, "accessRequests", REQUEST_ID)));
  });
});

describe("accessRequests — unauthenticated", () => {
  test("cannot read any request", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "accessRequests", REQUEST_ID)));
  });
});

// ─────────────────────────────────────────────
// activeCheckIns — user reads own; no writes
// ─────────────────────────────────────────────

describe("activeCheckIns — owner", () => {
  test("can read own check-in", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, "activeCheckIns", CHECKIN_ID)));
  });

  test("cannot write a check-in directly", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, "activeCheckIns", "new-chk"), { ...fakeCheckInDoc(), checkInId: "new-chk" })
    );
  });

  test("cannot delete own check-in", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(deleteDoc(doc(db, "activeCheckIns", CHECKIN_ID)));
  });
});

describe("activeCheckIns — other user", () => {
  test("cannot read another user's check-in", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, "activeCheckIns", CHECKIN_ID)));
  });
});

// ─────────────────────────────────────────────
// accessPassRateLimits — deny all direct access
// ─────────────────────────────────────────────

describe("accessPassRateLimits — deny all", () => {
  test("authenticated user cannot read their own rate limit doc", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(getDoc(doc(db, "accessPassRateLimits", OWNER_UID)));
  });

  test("authenticated user cannot write rate limit docs", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(setDoc(doc(db, "accessPassRateLimits", OWNER_UID), { count: 0 }));
  });

  test("unauthenticated cannot read rate limit docs", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "accessPassRateLimits", OWNER_UID)));
  });
});
