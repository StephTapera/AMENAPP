/**
 * noteShareAccess.rules.test.js — Verification suite (NEW, additive)
 *
 * Exercises the CANONICAL deployed rules (repo-root firestore.rules):
 *   • NoteShare access control (revoked / connections / church / signed-out)
 *   • User settings owner-only access
 *
 * RUN (one command):
 *   cd Backend && firebase emulators:exec --only firestore \
 *     "npx jest --testPathPattern=verification/ --testEnvironment node"
 *
 * Deps (Backend devDependencies): @firebase/rules-unit-testing ^3, firebase ^10, jest.
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
    require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

const PROJECT_ID = "amen-noteshare-verify";
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

const AUTHOR = "author-uid";
const READER = "reader-uid";
const activeShare = (visibility, extra = {}) =>
    ({ status: "active", authorUid: AUTHOR, shareConfig: { visibility, ...extra } });

describe("NoteShare access control (canonical firestore.rules)", () => {
    test("noteShare_revoked_returns_nothing", async () => {
        await seed("noteShares/s1", { ...activeShare("public"), status: "revoked" });
        await assertFails(dbAs(READER).collection("noteShares").doc("s1").get());
    });
    test("noteShare_signedOut_blocked_entirely", async () => {
        await seed("noteShares/s2", activeShare("public"));
        await assertFails(dbAnon().collection("noteShares").doc("s2").get());
    });
    test("noteShare_public_allowed_for_signedIn", async () => {
        await seed("noteShares/s3", activeShare("public"));
        await assertSucceeds(dbAs(READER).collection("noteShares").doc("s3").get());
    });
    test("noteShare_nonConnection_blocked_from_connections_visibility", async () => {
        await seed("noteShares/s4", activeShare("followers"));
        await assertFails(dbAs(READER).collection("noteShares").doc("s4").get());
    });
    test("noteShare_connection_allowed_for_connections_visibility", async () => {
        // Rule hardened to isMutualConnectionWith: BOTH follows_index edges required.
        await seed("noteShares/s5", activeShare("followers"));
        await seed(`follows_index/${READER}_${AUTHOR}`, { exists: true });
        await seed(`follows_index/${AUTHOR}_${READER}`, { exists: true });
        await assertSucceeds(dbAs(READER).collection("noteShares").doc("s5").get());
    });
    test("noteShare_nonMember_blocked_from_church_visibility", async () => {
        // Rule hardened to isOrganizationMember: a client churchId claim is NOT the
        // predicate — only a real organizations/{orgId}/members/{uid} edge grants read.
        await seed("noteShares/s6", activeShare("church", { churchId: "org-1" }));
        await assertFails(dbAs(READER, { churchId: "org-1" }).collection("noteShares").doc("s6").get());
    });
    test("noteShare_member_allowed_for_church_visibility", async () => {
        await seed("noteShares/s7", activeShare("church", { churchId: "org-1" }));
        await seed(`organizations/org-1/members/${READER}`, { status: "active", role: "member" });
        await assertSucceeds(dbAs(READER).collection("noteShares").doc("s7").get());
    });
    test("noteShare_author_allowed_when_active", async () => {
        await seed("noteShares/s8", activeShare("followers"));
        await assertSucceeds(dbAs(AUTHOR).collection("noteShares").doc("s8").get());
    });
    test("noteShare_list_denied", async () => {
        await seed("noteShares/s9", activeShare("public"));
        await assertFails(dbAs(READER).collection("noteShares").get());
    });
    test("noteShare_clientWrite_denied", async () => {
        await assertFails(dbAs(AUTHOR).collection("noteShares").doc("s10").set(activeShare("public")));
    });
});

describe("User settings owner-only access", () => {
    test("settings_owner_can_read", async () => {
        await seed(`users/${READER}/settings/messaging`, { readReceipts: true });
        await assertSucceeds(dbAs(READER).collection("users").doc(READER).collection("settings").doc("messaging").get());
    });
    test("settings_owner_can_write", async () => {
        await assertSucceeds(dbAs(READER).collection("users").doc(READER).collection("settings").doc("messaging").set({ readReceipts: false }));
    });
    test("settings_nonOwner_read_blocked", async () => {
        await seed(`users/${AUTHOR}/settings/messaging`, { readReceipts: true });
        await assertFails(dbAs(READER).collection("users").doc(AUTHOR).collection("settings").doc("messaging").get());
    });
    test("settings_nonOwner_write_blocked", async () => {
        await assertFails(dbAs(READER).collection("users").doc(AUTHOR).collection("settings").doc("messaging").set({ readReceipts: true }));
    });
    test("settings_signedOut_blocked", async () => {
        await seed(`users/${READER}/settings/messaging`, { readReceipts: true });
        await assertFails(dbAnon().collection("users").doc(READER).collection("settings").doc("messaging").get());
    });
});
