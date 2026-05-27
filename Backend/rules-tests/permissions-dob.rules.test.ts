import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, Timestamp } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-permissions-dob";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "dob-owner";
const OTHER_UID = "dob-other";

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
      uid: OWNER_UID,
      username: "owner",
      accountStatus: "active",
    });
    await setDoc(doc(db, "users", OWNER_UID, "private", "safety"), {
      dateOfBirth: Timestamp.fromDate(new Date("2000-01-01T00:00:00Z")),
      setAt: Timestamp.now(),
    });
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

describe("Permissions DOB safety document rules", () => {
  test("owner can read their private safety DOB document", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID, "private", "safety")));
  });

  test("non-owner cannot read another user's private safety DOB document", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "users", OWNER_UID, "private", "safety")));
  });

  test("owner cannot create, update, or overwrite private safety DOB document", async () => {
    const safetyRef = doc(dbAs(OWNER_UID), "users", OWNER_UID, "private", "safety");

    await assertFails(setDoc(safetyRef, {
      dateOfBirth: Timestamp.fromDate(new Date("1999-01-01T00:00:00Z")),
      setAt: Timestamp.now(),
    }));

    await assertFails(updateDoc(safetyRef, {
      dateOfBirth: Timestamp.fromDate(new Date("1998-01-01T00:00:00Z")),
    }));
  });

  test("admin context can write private safety DOB document because Admin SDK bypasses rules", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await assertSucceeds(setDoc(doc(db, "users", OWNER_UID, "private", "safety"), {
        dateOfBirth: Timestamp.fromDate(new Date("2001-01-01T00:00:00Z")),
        setAt: Timestamp.now(),
      }, { merge: true }));
    });
  });

  test("legacy private age_assurance document remains owner-writable for compatibility", async () => {
    await assertSucceeds(setDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID, "private", "age_assurance"), {
      tier: "adult",
      updatedAt: Timestamp.now(),
    }, { merge: true }));
  });
});
