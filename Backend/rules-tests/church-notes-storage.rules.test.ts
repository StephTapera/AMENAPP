import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-church-notes-storage";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/storage.rules");

const OWNER_UID = "church-note-storage-owner";
const OTHER_UID = "church-note-storage-other";
const NOTE_ID = "note-1";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

function storageAs(uid: string) {
  return testEnv.authenticatedContext(uid).storage("gs://amen-5e359.firebasestorage.app");
}

function uploadAs(uid: string, objectPath: string, contentType: string, bytes = 3): Promise<unknown> {
  return storageAs(uid)
    .ref(objectPath)
    .put(new Uint8Array(bytes), { contentType });
}

describe("Church Notes Intelligence Storage rules", () => {
  test("owner can upload allowed church note media", async () => {
    await assertSucceeds(uploadAs(
      OWNER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/audio/audio-1.m4a`,
      "audio/m4a"
    ));
    await assertSucceeds(uploadAs(
      OWNER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/video/video-1.mp4`,
      "video/mp4"
    ));
    await assertSucceeds(uploadAs(
      OWNER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/images/image-1.jpg`,
      "image/jpeg"
    ));
    await assertSucceeds(uploadAs(
      OWNER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/documents/doc-1.pdf`,
      "application/pdf"
    ));
  });

  test("unauthorized user cannot upload or read owner church note media", async () => {
    await assertFails(uploadAs(
      OTHER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/audio/audio-2.m4a`,
      "audio/m4a"
    ));

    await assertSucceeds(uploadAs(
      OWNER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/images/private.jpg`,
      "image/jpeg"
    ));

    await assertFails(storageAs(OTHER_UID)
      .ref(`churchNotes/${OWNER_UID}/${NOTE_ID}/images/private.jpg`)
      .getDownloadURL());
  });

  test("storage denies unsupported church note document types", async () => {
    await assertFails(uploadAs(
      OWNER_UID,
      `churchNotes/${OWNER_UID}/${NOTE_ID}/documents/slides.pptx`,
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    ));
  });
});
