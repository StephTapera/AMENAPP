import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-spiritual-os";
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "spiritual-owner";
const OTHER_UID = "spiritual-other";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES_PATH, "utf8"),
      host: firestoreEmulator.host,
      port: firestoreEmulator.port,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "spiritualOS_digest", OWNER_UID, "items", "digest-1"), {
      title: "Morning",
      isRead: false,
    });
    await setDoc(doc(db, "spiritualOS_hub", OWNER_UID, "items", "hub-1"), {
      title: "Prayer request",
      isPinned: false,
      isRead: false,
      isArchived: false,
    });
    await setDoc(doc(db, "spiritualOS_planner", OWNER_UID, "events", "event-1"), {
      title: "Study",
      isCompleted: false,
      isDismissed: false,
      color: "gold",
    });
    await setDoc(doc(db, "spiritualOS_suggestions", OWNER_UID, "items", "suggestion-1"), {
      title: "Read Romans 12",
      isDismissed: false,
    });
    await setDoc(doc(db, "spiritualOS_commandCenter", OWNER_UID, "aggregates", "aggregate-1"), {
      title: "Private formation",
      isDismissed: false,
    });
    await setDoc(doc(db, "spiritualOS_spaceCreateDrafts", OWNER_UID, "drafts", "draft-1"), {
      userId: OWNER_UID,
      name: "Prayer Team",
      status: "draft",
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

describe("Spiritual OS Firestore rules", () => {
  test("owner can read Spiritual OS private documents, but other users cannot", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "spiritualOS_digest", OWNER_UID, "items", "digest-1")));
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "spiritualOS_hub", OWNER_UID, "items", "hub-1")));
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "spiritualOS_planner", OWNER_UID, "events", "event-1")));

    await assertFails(getDoc(doc(dbAs(OTHER_UID), "spiritualOS_digest", OWNER_UID, "items", "digest-1")));
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "spiritualOS_hub", OWNER_UID, "items", "hub-1")));
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "spiritualOS_planner", OWNER_UID, "events", "event-1")));
  });

  test("server-owned collections deny client creates but allow narrow owner state updates", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "spiritualOS_digest", OWNER_UID, "items", "digest-2"), {
      title: "Client forged",
      isRead: false,
    }));

    await assertSucceeds(updateDoc(doc(dbAs(OWNER_UID), "spiritualOS_digest", OWNER_UID, "items", "digest-1"), {
      isRead: true,
    }));
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "spiritualOS_digest", OWNER_UID, "items", "digest-1"), {
      title: "Tampered",
    }));

    await assertSucceeds(updateDoc(doc(dbAs(OWNER_UID), "spiritualOS_hub", OWNER_UID, "items", "hub-1"), {
      isPinned: true,
    }));
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "spiritualOS_hub", OWNER_UID, "items", "hub-1"), {
      title: "Tampered",
    }));
  });

  test("planner and draft paths are owner-scoped and schema constrained", async () => {
    await assertSucceeds(setDoc(doc(dbAs(OWNER_UID), "spiritualOS_planner", OWNER_UID, "events", "event-2"), {
      title: "Serve team",
      startDate: 1782000000,
    }));
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "spiritualOS_planner", OWNER_UID, "events", "event-3"), {
      title: "Forged",
      bereanNote: "server-only",
    }));
    await assertFails(deleteDoc(doc(dbAs(OTHER_UID), "spiritualOS_spaceCreateDrafts", OWNER_UID, "drafts", "draft-1")));
  });

  test("context is server-written and command center exposes only dismissal updates", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "spiritualOS_context", OWNER_UID), {
      currentMode: "worship",
    }));

    await assertSucceeds(updateDoc(doc(dbAs(OWNER_UID), "spiritualOS_commandCenter", OWNER_UID, "aggregates", "aggregate-1"), {
      isDismissed: true,
    }));
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "spiritualOS_commandCenter", OWNER_UID, "aggregates", "aggregate-1"), {
      title: "Public metric",
    }));
  });
});
