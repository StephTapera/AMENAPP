import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-cn-media-processing";
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const OWNER_UID = "processing-owner";
const COLLABORATOR_UID = "processing-collaborator";
const OTHER_UID = "processing-other";
const NOTE_ID = "media-note-1";
const JOB_ID = "job-1";

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
    await setDoc(doc(db, "churchNotes", NOTE_ID), {
      userId: OWNER_UID,
      title: "Sermon notes",
      createdAt: 1,
      updatedAt: 1,
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "collaborators", COLLABORATOR_UID), {
      uid: COLLABORATOR_UID,
      role: "viewer",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
      jobId: JOB_ID,
      userId: OWNER_UID,
      churchNoteId: NOTE_ID,
      sourceType: "audio",
      status: "queued",
      progress: 0,
      transcriptText: null,
      ocrText: null,
      safetyStatus: "pending",
      moderationStatus: "pending",
      createdAt: 1,
      updatedAt: 1,
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

function dbAnon() {
  return testEnv.unauthenticatedContext().firestore();
}

describe("processingJobs -- read access", () => {

  test("unauthenticated user cannot read a processingJob", async () => {
    await assertFails(
      getDoc(doc(dbAnon(), "churchNotes", NOTE_ID, "processingJobs", JOB_ID))
    );
  });

  test("non-owner non-collaborator cannot read a processingJob", async () => {
    await assertFails(
      getDoc(doc(dbAs(OTHER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID))
    );
  });

  test("owner can read their own processingJob", async () => {
    await assertSucceeds(
      getDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID))
    );
  });

  test("collaborator with viewer role can read a processingJob", async () => {
    await assertSucceeds(
      getDoc(doc(dbAs(COLLABORATOR_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID))
    );
  });

});

describe("processingJobs -- create access", () => {

  test("owner cannot directly create a processingJob (callable-only path)", async () => {
    await assertFails(
      setDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", "client-created-job"), {
        jobId: "client-created-job",
        userId: OWNER_UID,
        churchNoteId: NOTE_ID,
        sourceType: "audio",
        status: "queued",
        safetyStatus: "pending",
        createdAt: 1,
        updatedAt: 1,
      })
    );
  });

  test("other user cannot create a processingJob on a note they do not own", async () => {
    await assertFails(
      setDoc(doc(dbAs(OTHER_UID), "churchNotes", NOTE_ID, "processingJobs", "injected-job"), {
        jobId: "injected-job",
        userId: OTHER_UID,
        status: "queued",
      })
    );
  });

});

describe("processingJobs -- update (cancel-only)", () => {

  test("owner can cancel a processingJob (status=canceled + updatedAt)", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        status: "canceled",
        updatedAt: 2,
      })
    );
  });

  test("owner can cancel with status field only (no updatedAt)", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        status: "canceled",
      })
    );
  });

  test("owner cannot set status to a value other than canceled", async () => {
    await assertFails(
      updateDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        status: "approved",
        updatedAt: 2,
      })
    );
  });

  test("owner cannot update a server-owned field (transcriptText)", async () => {
    await assertFails(
      updateDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        transcriptText: "injected transcript",
      })
    );
  });

  test("client cannot bundle cancel with a server-owned field injection", async () => {
    await assertFails(
      updateDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        status: "canceled",
        transcriptText: "injected while canceling",
        updatedAt: 2,
      })
    );
  });

  test("non-owner cannot cancel a processingJob", async () => {
    await assertFails(
      updateDoc(doc(dbAs(OTHER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        status: "canceled",
        updatedAt: 2,
      })
    );
  });

  test("collaborator cannot cancel a processingJob (cancel is owner-only)", async () => {
    await assertFails(
      updateDoc(doc(dbAs(COLLABORATOR_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID), {
        status: "canceled",
        updatedAt: 2,
      })
    );
  });

});

describe("processingJobs -- delete access", () => {

  test("owner cannot delete a processingJob (explicit deny)", async () => {
    await assertFails(
      deleteDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID))
    );
  });

  test("other user cannot delete a processingJob", async () => {
    await assertFails(
      deleteDoc(doc(dbAs(OTHER_UID), "churchNotes", NOTE_ID, "processingJobs", JOB_ID))
    );
  });

});
