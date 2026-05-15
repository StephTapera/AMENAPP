import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-church-notes";
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "church-note-owner";
const EDITOR_UID = "church-note-editor";
const COMMENTER_UID = "church-note-commenter";
const VIEWER_UID = "church-note-viewer";
const OTHER_UID = "church-note-other";
const NOTE_ID = "note-1";

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
      schemaVersion: 2,
      title: "Sermon notes",
      body: "Approved body",
      approvedBody: "Approved body",
      isPublic: false,
      updatedAt: 1,
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "collaborators", EDITOR_UID), {
      uid: EDITOR_UID,
      role: "editor",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "collaborators", COMMENTER_UID), {
      uid: COMMENTER_UID,
      role: "commenter",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "collaborators", VIEWER_UID), {
      uid: VIEWER_UID,
      role: "viewer",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "processingJobs", "job-1"), {
      status: "draftReady",
      sourceType: "audio",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "transcripts", "transcript-1"), {
      transcriptText: "Blessed are the meek.",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "ocrResults", "ocr-1"), {
      extractedText: "John 3:16",
    });
    await setDoc(doc(db, "churchNotes", NOTE_ID, "aiDrafts", "draft-1"), {
      summaryDraft: "Suggested summary",
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe("Church Notes Intelligence Firestore rules", () => {
  test("private notes are private to non-collaborators", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "churchNotes", NOTE_ID)));
  });

  test("owner can read and update allowed note fields", async () => {
    const ownerDb = dbAs(OWNER_UID);
    await assertSucceeds(getDoc(doc(ownerDb, "churchNotes", NOTE_ID)));
    await assertSucceeds(updateDoc(doc(ownerDb, "churchNotes", NOTE_ID), {
      title: "Updated sermon notes",
      approvedBody: "Approved edited body",
      updatedAt: 2,
    }));
  });

  test("clients cannot write AI system fields on the note", async () => {
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "churchNotes", NOTE_ID), {
      summaryDraft: "client generated",
    }));
  });

  test("clients cannot write transcripts, OCR results, AI drafts, or processing status", async () => {
    const ownerDb = dbAs(OWNER_UID);
    await assertFails(setDoc(doc(ownerDb, "churchNotes", NOTE_ID, "transcripts", "client"), {
      transcriptText: "client write",
    }));
    await assertFails(setDoc(doc(ownerDb, "churchNotes", NOTE_ID, "ocrResults", "client"), {
      extractedText: "client write",
    }));
    await assertFails(setDoc(doc(ownerDb, "churchNotes", NOTE_ID, "aiDrafts", "client"), {
      summaryDraft: "client write",
    }));
    await assertFails(updateDoc(doc(ownerDb, "churchNotes", NOTE_ID, "processingJobs", "job-1"), {
      status: "approved",
    }));
  });

  test("collaborators can read based on role", async () => {
    await assertSucceeds(getDoc(doc(dbAs(EDITOR_UID), "churchNotes", NOTE_ID)));
    await assertSucceeds(getDoc(doc(dbAs(COMMENTER_UID), "churchNotes", NOTE_ID)));
    await assertSucceeds(getDoc(doc(dbAs(VIEWER_UID), "churchNotes", NOTE_ID)));
  });

  test("viewer cannot edit note body", async () => {
    await assertFails(updateDoc(doc(dbAs(VIEWER_UID), "churchNotes", NOTE_ID), {
      approvedBody: "viewer edit",
      updatedAt: 3,
    }));
  });

  test("commenter can comment only", async () => {
    const commenterDb = dbAs(COMMENTER_UID);
    await assertSucceeds(setDoc(doc(commenterDb, "churchNotes", NOTE_ID, "comments", "comment-1"), {
      id: "comment-1",
      noteId: NOTE_ID,
      anchorText: "Approved",
      anchorStart: 0,
      anchorEnd: 8,
      body: "Helpful",
      authorUid: COMMENTER_UID,
      authorName: "Commenter",
      resolved: false,
      createdAt: 1,
      updatedAt: 1,
    }));
    await assertFails(updateDoc(doc(commenterDb, "churchNotes", NOTE_ID), {
      approvedBody: "commenter edit",
      updatedAt: 4,
    }));
  });

  test("editor can edit approved note body", async () => {
    await assertSucceeds(updateDoc(doc(dbAs(EDITOR_UID), "churchNotes", NOTE_ID), {
      approvedBody: "editor edit",
      updatedAt: 5,
    }));
  });

  test("viewer cannot create comments", async () => {
    await assertFails(setDoc(doc(dbAs(VIEWER_UID), "churchNotes", NOTE_ID, "comments", "viewer-comment"), {
      id: "viewer-comment",
      noteId: NOTE_ID,
      body: "viewer comment",
      authorUid: VIEWER_UID,
      resolved: false,
      createdAt: 1,
      updatedAt: 1,
    }));
  });

  test("comment author can delete own comment", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churchNotes", NOTE_ID, "comments", "owned-comment"), {
        id: "owned-comment",
        noteId: NOTE_ID,
        body: "delete me",
        authorUid: COMMENTER_UID,
        resolved: false,
        createdAt: 1,
        updatedAt: 1,
      });
    });

    await assertSucceeds(deleteDoc(doc(dbAs(COMMENTER_UID), "churchNotes", NOTE_ID, "comments", "owned-comment")));
    await assertFails(deleteDoc(doc(dbAs(EDITOR_UID), "churchNotes", NOTE_ID, "comments", "owned-comment")));
  });
});
