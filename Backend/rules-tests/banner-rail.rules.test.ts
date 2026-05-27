import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-banner-rail";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

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
    await setDoc(doc(db, "bannerSources", "approved"), {
      title: "Young Adults Night",
      subtitle: "Friday",
      createdBy: "author-1",
      moderationStatus: "approved",
      visibility: "authenticated",
      surfaceAllowlist: ["spacesHome"],
    });
    await setDoc(doc(db, "bannerSources", "pending"), {
      title: "Pending Group",
      subtitle: "Needs review",
      createdBy: "author-1",
      moderationStatus: "pending",
      visibility: "authenticated",
      surfaceAllowlist: ["spacesHome"],
    });
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid, {
    email_verified: true,
    firebase: { sign_in_provider: "password" },
  }).firestore();
}

describe("Selah banner rail Firestore rules", () => {
  test("approved banners are readable and pending banners are not", async () => {
    await assertSucceeds(getDoc(doc(dbAs("viewer-1"), "bannerSources", "approved")));
    await assertFails(getDoc(doc(dbAs("viewer-1"), "bannerSources", "pending")));
  });

  test("authors can submit pending banners but cannot self-approve", async () => {
    await assertSucceeds(setDoc(doc(dbAs("author-1"), "bannerSources", "new-pending"), {
      title: "Submitted Banner",
      subtitle: "Pending",
      createdBy: "author-1",
      moderationStatus: "pending",
      visibility: "authenticated",
      surfaceAllowlist: ["spacesHome"],
    }));

    await assertFails(updateDoc(doc(dbAs("author-1"), "bannerSources", "pending"), {
      moderationStatus: "approved",
    }));
  });

  test("users can write only their own banner display preferences", async () => {
    await assertSucceeds(setDoc(doc(dbAs("uid-1"), "bannerDisplayPreferences", "uid-1"), {
      sizesBySurface: { spacesHome: "standard" },
    }));

    await assertFails(setDoc(doc(dbAs("uid-1"), "bannerDisplayPreferences", "uid-2"), {
      sizesBySurface: { spacesHome: "hero" },
    }));
  });
});
