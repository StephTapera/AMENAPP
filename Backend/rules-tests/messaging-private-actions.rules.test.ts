import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, Timestamp, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-messaging-private-actions";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "owner-uid";
const OTHER_PARTICIPANT_UID = "other-participant-uid";
const NON_PARTICIPANT_UID = "non-participant-uid";

let testEnv: RulesTestEnvironment;

function privateNote() {
  return {
    noteId: "note-1",
    ownerUid: OWNER_UID,
    title: "Message note",
    body: "Private note body",
    visibility: "private",
    aiAssisted: false,
    source: {
      surface: "messaging",
      conversationId: "conversation-1",
      messageId: "message-1",
    },
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };
}

function reminder() {
  return {
    reminderId: "reminder-1",
    ownerUid: OWNER_UID,
    title: "Message reminder",
    note: "Private reminder note",
    visibility: "private",
    dueAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
    source: {
      surface: "messaging",
      conversationId: "conversation-1",
      messageId: "message-1",
    },
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };
}

function selahReflection() {
  return {
    reflectionId: "reflection-1",
    ownerUid: OWNER_UID,
    title: "Message reflection",
    text: "Private reflection body",
    visibility: "private",
    aiAssisted: false,
    source: {
      surface: "messaging",
      conversationId: "conversation-1",
      messageId: "message-1",
    },
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

describe("Amen Messaging private note rules", () => {
  test("owner can read/write a created private message note", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    const noteRef = doc(db, `users/${OWNER_UID}/privateMessageNotes/note-1`);

    await assertSucceeds(setDoc(noteRef, privateNote()));
    await assertSucceeds(getDoc(noteRef));
    await assertSucceeds(updateDoc(noteRef, { body: "Updated private note", updatedAt: Timestamp.now() }));
  });

  test("other participant cannot read private message note", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${OWNER_UID}/privateMessageNotes/note-1`), privateNote());
    });

    const db = testEnv.authenticatedContext(OTHER_PARTICIPANT_UID).firestore();
    await assertFails(getDoc(doc(db, `users/${OWNER_UID}/privateMessageNotes/note-1`)));
  });

  test("non-participant cannot read private message note", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${OWNER_UID}/privateMessageNotes/note-1`), privateNote());
    });

    const db = testEnv.authenticatedContext(NON_PARTICIPANT_UID).firestore();
    await assertFails(getDoc(doc(db, `users/${OWNER_UID}/privateMessageNotes/note-1`)));
  });
});

describe("Amen Messaging private reminder rules", () => {
  test("owner can read/write a message reminder", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    const reminderRef = doc(db, `users/${OWNER_UID}/messageReminders/reminder-1`);

    await assertSucceeds(setDoc(reminderRef, reminder()));
    await assertSucceeds(getDoc(reminderRef));
    await assertSucceeds(updateDoc(reminderRef, { title: "Updated reminder", updatedAt: Timestamp.now() }));
  });

  test("other participant cannot read reminder", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${OWNER_UID}/messageReminders/reminder-1`), reminder());
    });

    const db = testEnv.authenticatedContext(OTHER_PARTICIPANT_UID).firestore();
    await assertFails(getDoc(doc(db, `users/${OWNER_UID}/messageReminders/reminder-1`)));
  });
});

describe("Amen Messaging private Selah reflection rules", () => {
  test("owner can read Selah reflection", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    const reflectionRef = doc(db, `users/${OWNER_UID}/selahMessageReflections/reflection-1`);

    await assertSucceeds(setDoc(reflectionRef, selahReflection()));
    await assertSucceeds(getDoc(reflectionRef));
  });

  test("other participant cannot read Selah reflection", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${OWNER_UID}/selahMessageReflections/reflection-1`),
        selahReflection(),
      );
    });

    const db = testEnv.authenticatedContext(OTHER_PARTICIPANT_UID).firestore();
    await assertFails(getDoc(doc(db, `users/${OWNER_UID}/selahMessageReflections/reflection-1`)));
  });
});

