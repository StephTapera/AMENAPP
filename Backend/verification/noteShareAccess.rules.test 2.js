/**
 * noteShareAccess.rules.test.js — Verification suite (NEW, additive)
 *
 * Exercises the CANONICAL deployed rules (repo-root firestore.rules) for:
 *   • NoteShare access control (revoked / connections / church / signed-out)
 *   • User settings owner-only access
 *
 * NOTE: the older Backend/firestore.rules.test.js loads "AMENAPP/firestore 18.rules";
 * this file deliberately loads the repo-root firestore.rules (the deployed one).
 *
 * RUN (one command, after starting the emulator):
 *   cd Backend && firebase emulators:exec --only firestore \
 *     "npx jest --testPathPattern=verification/ --testEnvironment node"
 *
 * Or interactively:
 *   firebase emulators:start --only firestore     # terminal 1
 *   cd Backend && npx jest verification/noteShareAccess.rules.test.js   # terminal 2
 *
 * Deps (Backend devDependencies): @firebase/rules-unit-testing ^3, firebase ^10, jest.
 */

const {
    initializeTestEnvironment,
    assertFails,
    assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

const PROJECT_ID = "amen-noteshare-verify";
const RULES_PATH = resolve(__dirname, "../../firestore.rules"); // canonical root rules

let testEnv;

beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        firestore: {
            rules: readFileSync(RULES_PATH, "utf8"),
            host: "127.0.0.1",
            port: 8080,
        },
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
        for (let i = 0; i < parts.length - 1; i += 2) {
            ref = ref.collection(parts[i]).doc(parts[i + 1]);
        }
        await ref.set(data);
    });
}

const AUTHOR = "author-uid";
const READER = "reader-uid";

function activeShare(visibility, extraConfig = {}) {
    return {
        status: "active",
        authorUid: AUTHOR,
        shareConfig: { visibility, ...extraConfig },
    };
}

describe("NoteShare access control (canonical firestore.rules)", () => {
    test("noteShare_revoked_returns_nothing — non-active share denied even to a signed-in user", async () => {
        await seed("noteShares/s1", { ...activeShare("public"), status: "revoked" });
        await assertFails(dbAs(READER).collection("noteShares").doc("s1").get());
    });

    test("noteShare_signedOut_blocked_entirely — anonymous read denied", async () => {
        await seed("noteShares/s2", activeShare("public"));
        await assertFails(dbAnon().collection("noteShares").doc("s2").get());
    });

    test("noteShare_public_allowed_for_signedIn — baseline positive", async () => {
        await seed("noteShares/s3", activeShare("public"));
        await assertSucceeds(dbAs(READER).collection("noteShares").doc("s3").get());
    });

    test("noteShare_nonConnection_blocked_from_connections_visibility — followers, no follows_index edge", async () => {
        await seed("noteShares/s4", activeShare("followers"));
        await assertFails(dbAs(READER).collection("noteShares").doc("s4").get());
    });

    test("noteShare_connection_allowed_for_connections_visibility — followers, edge present", async () => {
        await seed("noteShares/s5", activeShare("followers"));
        await seed(`follows_index/${READER}_${AUTHOR}`, { exists: true });
        await assertSucceeds(dbAs(READER).collection("noteShares").doc("s5").get());
    });

    test("noteShare_nonMember_blocked_from_church_visibility — church, reader lacks matching churchId claim", async () => {
        await seed("noteShares/s6", activeShare("church", { churchId: "church-1" }));
        await assertFails(dbAs(READER, { churchId: "other-church" }).collection("noteShares").doc("s6").get());
    });

    test("noteShare_member_allowed_for_church_visibility — church, reader has matching churchId claim", async () => {
        await seed("noteShares/s7", activeShare("church", { churchId: "church-1" }));
        await assertSucceeds(dbAs(READER, { churchId: "church-1" }).collection("noteShares").doc("s7").get());
    });

    test("noteShare_author_allowed_when_active — author always reads their own active share", async () => {
        await seed("noteShares/s8", activeShare("followers"));
        await assertSucceeds(dbAs(AUTHOR).collection("noteShares").doc("s8").get());
    });

    test("noteShare_list_denied — list/query is never allowed on shares", async () => {
        await seed("noteShares/s9", activeShare("public"));
        await assertFails(dbAs(READER).collection("noteShares").get());
    });

    test("noteShare_clientWrite_denied — create/update/delete always denied to clients", async () => {
        await assertFails(dbAs(AUTHOR).collection("noteShares").doc("s10").set(activeShare("public")));
    });
});

describe("User settings owner-only access", () => {
    test("settings_owner_can_read — owner reads own settings/messaging", async () => {
        await seed(`users/${READER}/settings/messaging`, { readReceipts: true });
        await assertSucceeds(dbAs(READER).collection("users").doc(READER).collection("settings").doc("messaging").get());
    });

    test("settings_owner_can_write — owner round-trips own settings/messaging", async () => {
        await assertSucceeds(
            dbAs(READER).collection("users").doc(READER).collection("settings").doc("messaging").set({ readReceipts: false })
        );
    });

    test("settings_nonOwner_read_blocked — other user cannot read settings", async () => {
        await seed(`users/${AUTHOR}/settings/messaging`, { readReceipts: true });
        await assertFails(dbAs(READER).collection("users").doc(AUTHOR).collection("settings").doc("messaging").get());
    });

    test("settings_nonOwner_write_blocked — other user cannot write settings", async () => {
        await assertFails(
            dbAs(READER).collection("users").doc(AUTHOR).collection("settings").doc("messaging").set({ readReceipts: true })
        );
    });

    test("settings_signedOut_blocked — anonymous cannot read settings", async () => {
        await seed(`users/${READER}/settings/messaging`, { readReceipts: true });
        await assertFails(dbAnon().collection("users").doc(READER).collection("settings").doc("messaging").get());
    });
});
