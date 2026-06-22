/**
 * actionIntelligenceRules.test.js — Action Intelligence lane
 * Firestore Security Rules unit tests for the Action Intelligence object
 * collections written by the `executeAmenAction` callable.
 *
 * Requires the Firebase Emulator Suite:
 *   firebase emulators:start --only firestore
 *
 * Then run (from Backend/):
 *   npx jest --testPathPattern=actionIntelligenceRules.test.js --testEnvironment node
 *
 * Dependencies (Backend devDependencies):
 *   "@firebase/rules-unit-testing": "^3.0.0"
 *   "firebase": "^10.x"
 *
 * Invariant under test: every Action Intelligence collection is
 * SERVER-AUTHORITATIVE — there is NO client write path (create/update/delete
 * are admin-SDK only). Reads are owner-scoped; the audit log is fully opaque
 * to clients; the per-user memory graph is strictly private.
 */

const {
    initializeTestEnvironment,
    assertFails,
    assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

const PROJECT_ID = "amen-ai-rules-test";
// Canonical, deployed ruleset lives at the repo root.
const RULES_PATH = resolve(__dirname, "../firestore.rules");

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

afterAll(async () => {
    await testEnv.cleanup();
});

afterEach(async () => {
    await testEnv.clearFirestore();
});

function dbAs(uid) {
    return testEnv.authenticatedContext(uid).firestore();
}

function dbAnon() {
    return testEnv.unauthenticatedContext().firestore();
}

// Seed as admin (bypasses rules) — mirrors how the callable writes server-side.
async function seedDoc(path, data) {
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

const OWNER = "owner-uid";
const STRANGER = "stranger-uid";

// ── actionIntelligenceObjects — owner-only read, no client write ──────────────

describe("actionIntelligenceObjects — read access", () => {
    test("owner can read their own detected object", async () => {
        await seedDoc("actionIntelligenceObjects/obj-1", { ownerId: OWNER, objectClass: "need" });
        await assertSucceeds(dbAs(OWNER).collection("actionIntelligenceObjects").doc("obj-1").get());
    });

    test("a different signed-in user cannot read someone else's object", async () => {
        await seedDoc("actionIntelligenceObjects/obj-1", { ownerId: OWNER, objectClass: "need" });
        await assertFails(dbAs(STRANGER).collection("actionIntelligenceObjects").doc("obj-1").get());
    });

    test("anonymous user cannot read an object", async () => {
        await seedDoc("actionIntelligenceObjects/obj-1", { ownerId: OWNER, objectClass: "need" });
        await assertFails(dbAnon().collection("actionIntelligenceObjects").doc("obj-1").get());
    });
});

describe("actionIntelligenceObjects — no client write path", () => {
    test("client cannot create", async () => {
        await assertFails(
            dbAs(OWNER).collection("actionIntelligenceObjects").doc("obj-new").set({ ownerId: OWNER })
        );
    });

    test("owner cannot update their own object", async () => {
        await seedDoc("actionIntelligenceObjects/obj-1", { ownerId: OWNER, objectClass: "need" });
        await assertFails(
            dbAs(OWNER).collection("actionIntelligenceObjects").doc("obj-1").update({ objectClass: "moment" })
        );
    });

    test("owner cannot delete their own object", async () => {
        await seedDoc("actionIntelligenceObjects/obj-1", { ownerId: OWNER, objectClass: "need" });
        await assertFails(dbAs(OWNER).collection("actionIntelligenceObjects").doc("obj-1").delete());
    });
});

// ── actionIntelligenceAudit — fully opaque to clients ─────────────────────────

describe("actionIntelligenceAudit — opaque to all clients", () => {
    test("owner of the audited action cannot read the audit entry", async () => {
        await seedDoc("actionIntelligenceAudit/audit-1", { uid: OWNER, actionVerb: "pray_now" });
        await assertFails(dbAs(OWNER).collection("actionIntelligenceAudit").doc("audit-1").get());
    });

    test("client cannot write an audit entry", async () => {
        await assertFails(
            dbAs(OWNER).collection("actionIntelligenceAudit").doc("audit-new").set({ uid: OWNER })
        );
    });
});

// ── users/{uid}/amenMemoryGraph — strictly private, no client write ───────────

describe("amenMemoryGraph — strictly private", () => {
    test("owner can read their own memory node", async () => {
        await seedDoc(`users/${OWNER}/amenMemoryGraph/mem-1`, { summary: "follow up" });
        await assertSucceeds(
            dbAs(OWNER).collection("users").doc(OWNER).collection("amenMemoryGraph").doc("mem-1").get()
        );
    });

    test("another user cannot read someone else's memory node", async () => {
        await seedDoc(`users/${OWNER}/amenMemoryGraph/mem-1`, { summary: "follow up" });
        await assertFails(
            dbAs(STRANGER).collection("users").doc(OWNER).collection("amenMemoryGraph").doc("mem-1").get()
        );
    });

    test("owner cannot write their own memory node from the client", async () => {
        await assertFails(
            dbAs(OWNER).collection("users").doc(OWNER).collection("amenMemoryGraph").doc("mem-2").set({ summary: "x" })
        );
    });
});

// ── amenVolunteerAssignments — owner or assignee read, no client write ────────

describe("amenVolunteerAssignments — owner/assignee read", () => {
    const ASSIGNEE = "assignee-uid";

    test("owner can read the assignment", async () => {
        await seedDoc("amenVolunteerAssignments/asg-1", { ownerId: OWNER, assigneeId: ASSIGNEE });
        await assertSucceeds(dbAs(OWNER).collection("amenVolunteerAssignments").doc("asg-1").get());
    });

    test("assignee can read the assignment", async () => {
        await seedDoc("amenVolunteerAssignments/asg-1", { ownerId: OWNER, assigneeId: ASSIGNEE });
        await assertSucceeds(dbAs(ASSIGNEE).collection("amenVolunteerAssignments").doc("asg-1").get());
    });

    test("an unrelated user cannot read the assignment", async () => {
        await seedDoc("amenVolunteerAssignments/asg-1", { ownerId: OWNER, assigneeId: ASSIGNEE });
        await assertFails(dbAs(STRANGER).collection("amenVolunteerAssignments").doc("asg-1").get());
    });

    test("client cannot create an assignment", async () => {
        await assertFails(
            dbAs(OWNER).collection("amenVolunteerAssignments").doc("asg-new").set({ ownerId: OWNER, assigneeId: ASSIGNEE })
        );
    });
});

// ── amenRelationshipSignals — owner or target read, no client write ───────────

describe("amenRelationshipSignals — owner/target read", () => {
    const TARGET = "target-uid";

    test("owner can read the signal", async () => {
        await seedDoc("amenRelationshipSignals/sig-1", { ownerId: OWNER, targetUserId: TARGET });
        await assertSucceeds(dbAs(OWNER).collection("amenRelationshipSignals").doc("sig-1").get());
    });

    test("target can read the signal", async () => {
        await seedDoc("amenRelationshipSignals/sig-1", { ownerId: OWNER, targetUserId: TARGET });
        await assertSucceeds(dbAs(TARGET).collection("amenRelationshipSignals").doc("sig-1").get());
    });

    test("an unrelated user cannot read the signal", async () => {
        await seedDoc("amenRelationshipSignals/sig-1", { ownerId: OWNER, targetUserId: TARGET });
        await assertFails(dbAs(STRANGER).collection("amenRelationshipSignals").doc("sig-1").get());
    });

    test("client cannot create a signal", async () => {
        await assertFails(
            dbAs(OWNER).collection("amenRelationshipSignals").doc("sig-new").set({ ownerId: OWNER, targetUserId: TARGET })
        );
    });
});

// ── amenInitiatives — owner read, unrelated denied, no client write ───────────
// Positive space/church/org scope reads are covered by those collections' own
// membership suites; here we pin the owner-positive and stranger-negative paths.

describe("amenInitiatives — owner read + server-authoritative writes", () => {
    test("owner can read their initiative", async () => {
        await seedDoc("amenInitiatives/init-1", { ownerId: OWNER, source: {} });
        await assertSucceeds(dbAs(OWNER).collection("amenInitiatives").doc("init-1").get());
    });

    test("an unrelated user with no scope cannot read the initiative", async () => {
        await seedDoc("amenInitiatives/init-1", { ownerId: OWNER, source: {} });
        await assertFails(dbAs(STRANGER).collection("amenInitiatives").doc("init-1").get());
    });

    test("client cannot create an initiative", async () => {
        await assertFails(
            dbAs(OWNER).collection("amenInitiatives").doc("init-new").set({ ownerId: OWNER, source: {} })
        );
    });

    test("client cannot create a milestone under an initiative", async () => {
        await seedDoc("amenInitiatives/init-1", { ownerId: OWNER, source: {} });
        await assertFails(
            dbAs(OWNER).collection("amenInitiatives").doc("init-1").collection("milestones").doc("m-1").set({ title: "x" })
        );
    });
});

// ── amenKnowledgeGraph — owner read, unrelated denied, no client write ────────

describe("amenKnowledgeGraph — owner read + server-authoritative writes", () => {
    test("owner can read their node", async () => {
        await seedDoc("amenKnowledgeGraph/node-1", { ownerId: OWNER, scopeType: "user" });
        await assertSucceeds(dbAs(OWNER).collection("amenKnowledgeGraph").doc("node-1").get());
    });

    test("an unrelated user with no scope cannot read the node", async () => {
        await seedDoc("amenKnowledgeGraph/node-1", { ownerId: OWNER, scopeType: "user" });
        await assertFails(dbAs(STRANGER).collection("amenKnowledgeGraph").doc("node-1").get());
    });

    test("client cannot create a node", async () => {
        await assertFails(
            dbAs(OWNER).collection("amenKnowledgeGraph").doc("node-new").set({ ownerId: OWNER, scopeType: "user" })
        );
    });
});
