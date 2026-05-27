import { initializeTestEnvironment, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";

let testEnv: RulesTestEnvironment;

const projectId = "amen-selah-contracts-test";

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync("Selah/_contracts/firestore.rules", "utf8"),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function reflection(overrides: Record<string, unknown> = {}) {
  return {
    id: "reflection_1",
    ownerUid: "alice",
    verseId: "PSA.1.3",
    translation: "ESV",
    body: "A private reflection.",
    safetyTheme: "neutral",
    shareScope: "justMe",
    isShareEligible: true,
    relationalSignals: { prayedByGroupCount: 0 },
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  };
}

describe("Selah reflection rules", () => {
  it("lets the owner create a private reflection", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await expect(db.doc("reflections/reflection_1").set(reflection())).resolves.toBeUndefined();
  });

  it("blocks public-style sharing by allowing only scoped grants", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await expect(
      db.doc("reflections/reflection_1").set(reflection({ shareScope: "public" }))
    ).rejects.toThrow();
  });

  it("forces sensitive safety themes to stay private and ineligible for sharing", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await expect(
      db.doc("reflections/reflection_1").set(
        reflection({
          safetyTheme: "selfHarm",
          shareScope: "accountabilityPartner",
          sharedWithUid: "bob",
          isShareEligible: true,
        })
      )
    ).rejects.toThrow();
  });

  it("lets an accountability partner read only an explicitly shared reflection", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("reflections/reflection_1").set(
        reflection({ shareScope: "accountabilityPartner", sharedWithUid: "bob" })
      );
    });

    const bobDb = testEnv.authenticatedContext("bob").firestore();
    await expect(bobDb.doc("reflections/reflection_1").get()).resolves.toBeDefined();

    const charlieDb = testEnv.authenticatedContext("charlie").firestore();
    await expect(charlieDb.doc("reflections/reflection_1").get()).rejects.toThrow();
  });
});

describe("Selah cache and classifier rules", () => {
  it("blocks client writes to study sheet cache", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await expect(db.doc("studySheetCache/ESV_PSA_1_3_v1").set({ verseId: "PSA.1.3" })).rejects.toThrow();
  });

  it("blocks client writes to verse theme tags", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await expect(db.doc("verseThemeTags/ESV_PSA_1_3_v1").set({ verseId: "PSA.1.3" })).rejects.toThrow();
  });
});
