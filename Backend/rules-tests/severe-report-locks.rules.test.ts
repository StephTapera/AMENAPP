// severe-report-locks.rules.test.ts
//
// Focused, Firestore-only proof for the submitReport severe-report security
// control. Exists separately from trust-safety-launch.rules.test.ts because that
// suite currently fails to COMPILE on a pre-existing Storage-helper type error
// (UploadTask vs Promise), which blocks its Firestore assertions from ever
// running. This file has no Storage dependency, so the rejected-write evidence
// actually executes.
//
// Proves, against the SAME rules artifact firebase deploys (globalSetup
// regenerates firestore.deploy.rules from the canonical root firestore.rules):
//   1. Clients cannot create reports / userReports directly (CF submitReport only).
//   2. Clients cannot read OR write any of the four Tier-1 artifact collections.
//   3. The rules — including the newly added explicit lock blocks — compile.

import {
  assertFails,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-severe-report-locks";
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "severe-locks-owner";
const OTHER_UID = "severe-locks-other";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", OWNER_UID), { uid: OWNER_UID });
    await setDoc(doc(db, "users", OTHER_UID), { uid: OTHER_UID });
    await setDoc(doc(db, "moderationCases", "case-1"), { caseId: "case-1" });
    await setDoc(doc(db, "trustSafetyEvents", "event-1"), { type: "severe_report_received" });
    await setDoc(doc(db, "evidenceVault", "case-1"), { reportId: "case-1", legalHold: true });
    await setDoc(doc(db, "ncmecReadiness", "case-1"), { reportId: "case-1" });
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

describe("submitReport severe-report locks", () => {
  test("clients cannot bypass submitReport by writing report collections directly", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "reports", "direct-report"), {
      reporterId: OWNER_UID,
      reason: "child_safety",
      escalationTier: 1,
    }));

    await assertFails(setDoc(doc(dbAs(OWNER_UID), "userReports", "direct-user-report"), {
      reporterId: OWNER_UID,
      reportedUserId: OTHER_UID,
      reason: "child_safety",
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
