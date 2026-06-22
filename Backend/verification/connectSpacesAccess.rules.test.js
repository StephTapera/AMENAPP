/**
 * connectSpacesAccess.rules.test.js — ConnectSpaces prepared-ground tests (NEW, additive)
 *
 * Prepares backend access-control ground for the three ConnectSpaces stub
 * features (claude lane) BEFORE the Swift lands:
 *   1. Ministry Room file upload  → spaces/{spaceId}/files/{fileId}
 *   2. Location/proximity discovery → reads on spaces (public vs private)
 *   3. (CreatorHub tab — uses existing creator collections; not modeled here)
 *
 * Status:
 *   • "Space discovery" tests validate the EXISTING spaces rule (green now).
 *   • "Space files" tests encode the TARGET contract for the not-yet-added
 *     spaces/{spaceId}/files rule. They are RED until that rule is appended
 *     (TDD spec). REQUIRED RULE (append-only, for the rules batch):
 *
 *       match /spaces/{spaceId}/files/{fileId} {
 *         allow read: if isSpaceMember(spaceId) || isAdminSDK();
 *         allow create: if isSpaceMember(spaceId) &&
 *           request.resource.data.get('uploaderId','') == request.auth.uid;
 *         allow update, delete: if
 *           hasAnyClaimRole(['owner','pastor','leader','executive_admin']);
 *       }
 *
 * RUN:
 *   cd Backend && firebase emulators:exec --only firestore \
 *     "npx jest --testPathPattern=verification/ --testEnvironment node"
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
    require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

const PROJECT_ID = "amen-connectspaces-verify";
const RULES_PATH = resolve(__dirname, "../../firestore.rules");

let testEnv;
beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        firestore: { rules: readFileSync(RULES_PATH, "utf8"), host: "127.0.0.1", port: 8080 },
    });
});
afterAll(async () => { await testEnv.cleanup(); });
afterEach(async () => { await testEnv.clearFirestore(); });

const dbAs = (uid, claims = {}) => testEnv.authenticatedContext(uid, claims).firestore();
const dbAnon = () => testEnv.unauthenticatedContext().firestore();
async function seed(path, data) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        const parts = path.split("/");
        let ref = db;
        for (let i = 0; i < parts.length - 1; i += 2) ref = ref.collection(parts[i]).doc(parts[i + 1]);
        await ref.set(data);
    });
}

const MEMBER = "member-uid";
const STRANGER = "stranger-uid";
const SPACE = "space-1";

async function seedSpace({ privacyLevel = "public" } = {}) {
    await seed(`spaces/${SPACE}`, { privacyLevel, leaderId: "leader-uid", churchVerified: true });
}
async function joinSpace(uid) { await seed(`spaces/${SPACE}/members/${uid}`, { role: "member" }); }

describe("Space discovery / proximity (validates EXISTING spaces rule)", () => {
    test("discovery_signedIn_canRead_publicSpace", async () => {
        await seedSpace({ privacyLevel: "public" });
        await assertSucceeds(dbAs(STRANGER).collection("spaces").doc(SPACE).get());
    });
    test("discovery_nonMember_blocked_from_privateSpace", async () => {
        await seedSpace({ privacyLevel: "private" });
        await assertFails(dbAs(STRANGER).collection("spaces").doc(SPACE).get());
    });
    test("discovery_member_canRead_privateSpace", async () => {
        await seedSpace({ privacyLevel: "private" });
        await joinSpace(MEMBER);
        await assertSucceeds(dbAs(MEMBER).collection("spaces").doc(SPACE).get());
    });
    test("discovery_signedOut_blocked", async () => {
        await seedSpace({ privacyLevel: "public" });
        await assertFails(dbAnon().collection("spaces").doc(SPACE).get());
    });
});

describe("Ministry Room files — TARGET contract (RED until spaces/{id}/files rule is added)", () => {
    test("spaceFiles_member_canRead", async () => {
        await seedSpace(); await joinSpace(MEMBER);
        await seed(`spaces/${SPACE}/files/f1`, { name: "notes.pdf", uploaderId: MEMBER });
        await assertSucceeds(dbAs(MEMBER).collection("spaces").doc(SPACE).collection("files").doc("f1").get());
    });
    test("spaceFiles_member_canUpload_ownFile", async () => {
        await seedSpace(); await joinSpace(MEMBER);
        await assertSucceeds(
            dbAs(MEMBER).collection("spaces").doc(SPACE).collection("files").doc("f2").set({ name: "a.pdf", uploaderId: MEMBER })
        );
    });
    test("spaceFiles_nonMember_read_denied", async () => {
        await seedSpace();
        await seed(`spaces/${SPACE}/files/f3`, { name: "x.pdf", uploaderId: MEMBER });
        await assertFails(dbAs(STRANGER).collection("spaces").doc(SPACE).collection("files").doc("f3").get());
    });
    test("spaceFiles_signedOut_denied", async () => {
        await seedSpace();
        await seed(`spaces/${SPACE}/files/f4`, { name: "y.pdf", uploaderId: MEMBER });
        await assertFails(dbAnon().collection("spaces").doc(SPACE).collection("files").doc("f4").get());
    });
});
