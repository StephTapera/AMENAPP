import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-creator-role-denial";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");
const UID = "user_abc";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

function authedDb() {
  return testEnv.authenticatedContext(UID).firestore();
}

async function seedProfile() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${UID}`), {
      displayName: "A",
      bio: "seed",
    });
  });
}

describe("creator role self-write denial", () => {
  it("DENY create with roles.creator = true", async () => {
    await assertFails(
      setDoc(doc(authedDb(), `users/${UID}`), {
        displayName: "A",
        roles: { creator: true },
      })
    );
  });

  it("DENY update merge setting roles.creator = true", async () => {
    await seedProfile();

    await assertFails(
      setDoc(
        doc(authedDb(), `users/${UID}`),
        { roles: { creator: true } },
        { merge: true }
      )
    );
  });

  it("DENY each protected role and trust field", async () => {
    await seedProfile();

    const protectedPayloads: Array<Record<string, unknown>> = [
      { isCreator: true },
      { roles: { creator: true } },
      { role: "admin" },
      { isAdmin: true },
      { safety: { trusted: true } },
      { trustScore: 99 },
      { accountStatus: "staff" },
    ];

    for (const payload of protectedPayloads) {
      await assertFails(
        setDoc(doc(authedDb(), `users/${UID}`), payload, { merge: true })
      );
    }
  });

  it("ALLOW legitimate profile write without protected fields", async () => {
    await seedProfile();

    await assertSucceeds(
      setDoc(
        doc(authedDb(), `users/${UID}`),
        { displayName: "A2", bio: "hi" },
        { merge: true }
      )
    );
  });
});
