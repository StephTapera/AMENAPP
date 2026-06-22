import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, Timestamp, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator, storageEmulator, databaseEmulator, databaseUrl } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-berean-pulse";
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "berean-owner";
const OTHER_UID = "berean-other";
const DATE_KEY = "2026-01-01";

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
    await setDoc(bereanCardRef(db, OWNER_UID, "card-1"), {
      id: "card-1",
      userId: OWNER_UID,
      title: "Card",
      isHidden: false,
      updatedAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00.000Z")),
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

function bereanRootPath(uid: string) {
  return `users/${uid}/bereanPulse/main`;
}

function bereanCardRef(db: any, uid: string, cardId: string) {
  return doc(db, `${bereanRootPath(uid)}/days/${DATE_KEY}/cards/${cardId}`);
}

describe("Berean Pulse Firestore rules", () => {
  test("owners can read cards, but other users cannot", async () => {
    await assertSucceeds(getDoc(bereanCardRef(dbAs(OWNER_UID), OWNER_UID, "card-1")));
    await assertFails(getDoc(bereanCardRef(dbAs(OTHER_UID), OWNER_UID, "card-1")));
  });

  test("clients can only hide cards and cannot modify server-owned card fields", async () => {
    await assertSucceeds(updateDoc(bereanCardRef(dbAs(OWNER_UID), OWNER_UID, "card-1"), {
      isHidden: true,
      updatedAt: Timestamp.now(),
    }));

    await assertFails(updateDoc(bereanCardRef(dbAs(OWNER_UID), OWNER_UID, "card-1"), {
      title: "Tampered",
      updatedAt: Timestamp.now(),
    }));
  });

  test("preferences are owner-only and schema-limited", async () => {
    const ownerPreferenceRef = doc(dbAs(OWNER_UID), `${bereanRootPath(OWNER_UID)}/preferences/main`);
    await assertSucceeds(setDoc(ownerPreferenceRef, {
      enabled: true,
      preferredModes: ["spiritual", "work"],
      suppressedModes: ["wellness"],
      preferredTone: "strategic",
      preferredLength: "balanced",
      workModeEnabled: true,
    }));

    await assertFails(setDoc(ownerPreferenceRef, {
      enabled: true,
      tier: "admin",
      quota: 999999,
    }));

    await assertFails(setDoc(doc(dbAs(OTHER_UID), `${bereanRootPath(OWNER_UID)}/preferences/main`), {
      enabled: false,
    }));
  });

  test("permissions are owner-only and cannot carry protected fields", async () => {
    const ownerPermissionRef = doc(dbAs(OWNER_UID), `${bereanRootPath(OWNER_UID)}/permissions/main`);
    await assertSucceeds(setDoc(ownerPermissionRef, {
      bereanChatHistory: true,
      prayerJournal: false,
      updatedAt: Timestamp.now(),
    }, { merge: true }));

    await assertFails(setDoc(ownerPermissionRef, {
      bereanChatHistory: true,
      role: "admin",
    }, { merge: true }));
  });

  test("events are append-only, owner-only, and schema-limited", async () => {
    const eventRef = doc(dbAs(OWNER_UID), `${bereanRootPath(OWNER_UID)}/events/event-1`);
    await assertSucceeds(setDoc(eventRef, {
      cardId: "card-1",
      eventType: "liked",
      mode: "learning",
      timestamp: Timestamp.now(),
      metadata: { topicKey: "topic-1" },
    }));

    await assertFails(setDoc(doc(dbAs(OTHER_UID), `${bereanRootPath(OWNER_UID)}/events/event-2`), {
      cardId: "card-1",
      eventType: "liked",
      timestamp: Timestamp.now(),
    }));

    await assertFails(setDoc(doc(dbAs(OWNER_UID), `${bereanRootPath(OWNER_UID)}/events/event-3`), {
      cardId: "card-1",
      eventType: "adminOverride",
      timestamp: Timestamp.now(),
    }));

    await assertFails(updateDoc(eventRef, { eventType: "hidden" }));
  });

  test("saved cards are owner-only and cardId must match document id", async () => {
    const savedRef = doc(dbAs(OWNER_UID), `${bereanRootPath(OWNER_UID)}/savedCards/card-1`);
    await assertSucceeds(setDoc(savedRef, {
      cardId: "card-1",
      mode: "learning",
      title: "Card",
      savedAt: Timestamp.now(),
    }));

    await assertFails(setDoc(doc(dbAs(OWNER_UID), `${bereanRootPath(OWNER_UID)}/savedCards/card-2`), {
      cardId: "card-1",
      savedAt: Timestamp.now(),
    }));

    await assertFails(deleteDoc(doc(dbAs(OTHER_UID), `${bereanRootPath(OWNER_UID)}/savedCards/card-1`)));
  });
});
