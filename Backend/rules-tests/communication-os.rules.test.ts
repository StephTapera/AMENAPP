import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-communication-os";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const MEMBER_UID = "member-uid";
const OTHER_UID = "other-uid";
const ADMIN_UID = "admin-uid";
const THREAD_ID = "thread-1";
const GROUP_ID = "group-1";
const DISCUSSION_ID = "discussion-1";

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

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `threads/${THREAD_ID}`), {
      participantIds: [MEMBER_UID, ADMIN_UID],
      createdBy: "system",
    });
    await setDoc(doc(db, `threads/${THREAD_ID}/messages/message-1`), {
      text: "hello",
      createdByUid: MEMBER_UID,
    });
    await setDoc(doc(db, `threads/${THREAD_ID}/smartContext/main`), {
      createdBy: "system",
      summaryCount: 1,
    });
    await setDoc(doc(db, `threads/${THREAD_ID}/summaries/summary-1`), {
      createdBy: "system",
      summary: "Summary",
    });
    await setDoc(doc(db, `threads/${THREAD_ID}/decisions/decision-1`), {
      createdBy: "system",
      summary: "Potential decision",
    });

    await setDoc(doc(db, `groups/${GROUP_ID}`), {
      creatorId: ADMIN_UID,
    });
    await setDoc(doc(db, `groups/${GROUP_ID}/members/${MEMBER_UID}`), {
      userId: MEMBER_UID,
      role: "member",
    });
    await setDoc(doc(db, `groups/${GROUP_ID}/members/${ADMIN_UID}`), {
      userId: ADMIN_UID,
      role: "admin",
    });
    await setDoc(doc(db, `groups/${GROUP_ID}/discussions/${DISCUSSION_ID}`), {
      createdBy: "system",
    });
    await setDoc(doc(db, `groups/${GROUP_ID}/discussions/${DISCUSSION_ID}/pulse/main`), {
      createdBy: "system",
      activeTopic: "Launch",
    });
  });
});

describe("Communication OS thread rules", () => {
  test("member read is allowed", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, `threads/${THREAD_ID}/smartContext/main`)));
    await assertSucceeds(getDoc(doc(db, `threads/${THREAD_ID}/summaries/summary-1`)));
  });

  test("non-member read is denied", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, `threads/${THREAD_ID}/smartContext/main`)));
    await assertFails(getDoc(doc(db, `threads/${THREAD_ID}/messages/message-1`)));
  });

  test("client summary write is denied", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(setDoc(doc(db, `threads/${THREAD_ID}/summaries/forged`), {
      createdBy: "system",
      summary: "Forged",
    }));
  });

  test("client decision forge is denied", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(setDoc(doc(db, `threads/${THREAD_ID}/decisions/forged`), {
      createdBy: "system",
      summary: "Forged decision",
      status: "confirmed",
    }));
  });

  test("own presence update is allowed", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(setDoc(doc(db, `threads/${THREAD_ID}/presence/${MEMBER_UID}`), {
      state: "focus_mode",
      visibility: "members",
    }));
  });

  test("other presence update is denied", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(setDoc(doc(db, `threads/${THREAD_ID}/presence/${OTHER_UID}`), {
      state: "active_now",
      visibility: "members",
    }));
  });
});

describe("Communication OS group discussion rules", () => {
  test("group member pulse read is allowed", async () => {
    const db = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, `groups/${GROUP_ID}/discussions/${DISCUSSION_ID}/pulse/main`)));
  });

  test("non-group member pulse read is denied", async () => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, `groups/${GROUP_ID}/discussions/${DISCUSSION_ID}/pulse/main`)));
  });
});
