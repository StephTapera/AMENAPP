import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, Timestamp } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-contextual-action-layer";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore 18.rules");

const OWNER_UID = "context-owner";
const OTHER_UID = "context-other";

const CONTEXTUAL_COLLECTIONS = [
  "contextSelections",
  "contextActions",
  "ambientSuggestions",
  "contextualMemory",
  "timelineCompression",
  "savedContextThreads",
  "studyContinuity",
  "readingContinuity",
  "reflectionHistory",
  "voiceReflections",
];

let testEnv: RulesTestEnvironment;

function contextualDoc(collectionName: string) {
  return {
    userId: OWNER_UID,
    sourceSurface: "church_notes_editor",
    sourceId: "note-1",
    contentType: "note",
    action: "askBerean",
    title: "Ask Berean",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };
}

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
});

describe("Universal Berean contextual action layer rules", () => {
  test.each(CONTEXTUAL_COLLECTIONS)("owner can read own %s document", async (collectionName) => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${OWNER_UID}/${collectionName}/doc-1`),
        contextualDoc(collectionName),
      );
    });

    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(getDoc(doc(db, `users/${OWNER_UID}/${collectionName}/doc-1`)));
  });

  test.each(CONTEXTUAL_COLLECTIONS)("other user cannot read %s document", async (collectionName) => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${OWNER_UID}/${collectionName}/doc-1`),
        contextualDoc(collectionName),
      );
    });

    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(getDoc(doc(db, `users/${OWNER_UID}/${collectionName}/doc-1`)));
  });

  test.each(CONTEXTUAL_COLLECTIONS)("owner cannot directly write backend-owned %s document", async (collectionName) => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, `users/${OWNER_UID}/${collectionName}/doc-1`), contextualDoc(collectionName)),
    );
  });

  test.each(CONTEXTUAL_COLLECTIONS)("cross-user writes fail for %s", async (collectionName) => {
    const db = testEnv.authenticatedContext(OTHER_UID).firestore();
    await assertFails(
      setDoc(doc(db, `users/${OWNER_UID}/${collectionName}/doc-1`), contextualDoc(collectionName)),
    );
  });
});
