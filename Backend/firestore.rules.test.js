/**
 * firestore.rules.test.js — System 29: Liquid Glass Intelligence Layer
 * Firestore Security Rules unit tests.
 *
 * Requires the Firebase Emulator Suite:
 *   firebase emulators:start --only firestore
 *
 * Then run:
 *   cd Backend && npm run test:rules
 *
 * Add to Backend/package.json scripts:
 *   "test:rules": "jest --testPathPattern=firestore.rules.test.js --testEnvironment node"
 *
 * Dependencies (add to Backend devDependencies):
 *   "@firebase/rules-unit-testing": "^3.0.0"
 *   "firebase": "^10.x"
 */

const {
    initializeTestEnvironment,
    assertFails,
    assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { readFileSync } = require("fs");
const { resolve } = require("path");

// ── Test environment setup ────────────────────────────────────────────────────

const PROJECT_ID = "amen-rules-test";
const RULES_PATH = resolve(__dirname, "../AMENAPP/firestore 18.rules");

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

// ── Helper: create Firestore client for a given user identity ─────────────────

function dbAs(uid) {
    return testEnv.authenticatedContext(uid).firestore();
}

function dbAnon() {
    return testEnv.unauthenticatedContext().firestore();
}

// ── Seed helper: write data as the admin (bypasses rules) ─────────────────────

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

// ── ─────────────────────────────────────────────────────────────────────────
// semanticDefinitions — shared, server-written, approved-only reads
// ── ─────────────────────────────────────────────────────────────────────────

describe("semanticDefinitions — read access", () => {

    test("authenticated user can read an approved definition", async () => {
        await seedDoc("semanticDefinitions/def-1", {
            term: "grace",
            safetyStatus: "approved",
            compactDefinition: "Unmerited favour.",
        });
        const db = dbAs("user-a");
        await assertSucceeds(db.collection("semanticDefinitions").doc("def-1").get());
    });

    test("unauthenticated user cannot read a definition", async () => {
        await seedDoc("semanticDefinitions/def-1", {
            term: "grace",
            safetyStatus: "approved",
            compactDefinition: "Unmerited favour.",
        });
        const db = dbAnon();
        await assertFails(db.collection("semanticDefinitions").doc("def-1").get());
    });

    test("authenticated user cannot read a definition with review_required status", async () => {
        await seedDoc("semanticDefinitions/def-pending", {
            term: "holiness",
            safetyStatus: "review_required",
            compactDefinition: "Being set apart.",
        });
        const db = dbAs("user-a");
        await assertFails(db.collection("semanticDefinitions").doc("def-pending").get());
    });

});

describe("semanticDefinitions — write access", () => {

    test("client cannot create a semantic definition", async () => {
        const db = dbAs("user-a");
        await assertFails(
            db.collection("semanticDefinitions").doc("def-new").set({
                term: "grace",
                safetyStatus: "approved",
                compactDefinition: "Fabricated by client.",
            })
        );
    });

    test("client cannot update a semantic definition", async () => {
        await seedDoc("semanticDefinitions/def-1", {
            term: "grace",
            safetyStatus: "approved",
            compactDefinition: "Unmerited favour.",
        });
        const db = dbAs("user-a");
        await assertFails(
            db.collection("semanticDefinitions").doc("def-1").update({
                safetyStatus: "approved",
                compactDefinition: "Modified by client.",
            })
        );
    });

    test("client cannot delete a semantic definition", async () => {
        await seedDoc("semanticDefinitions/def-1", {
            term: "grace",
            safetyStatus: "approved",
        });
        const db = dbAs("user-a");
        await assertFails(db.collection("semanticDefinitions").doc("def-1").delete());
    });

});

// ── ─────────────────────────────────────────────────────────────────────────
// users/{uid}/semanticInsights — user-scoped, server-created
// ── ─────────────────────────────────────────────────────────────────────────

describe("semanticInsights — read access", () => {

    test("owner can read their own semanticInsight", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            definitionId: "def-1",
            visibility: "private",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a").collection("semanticInsights").doc("ins-1").get()
        );
    });

    test("other user cannot read someone else's semanticInsight", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            definitionId: "def-1",
            visibility: "private",
            uid: "user-a",
        });
        const db = dbAs("user-b");
        await assertFails(
            db.collection("users").doc("user-a").collection("semanticInsights").doc("ins-1").get()
        );
    });

    test("unauthenticated user cannot read semanticInsights", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            uid: "user-a",
        });
        const db = dbAnon();
        await assertFails(
            db.collection("users").doc("user-a").collection("semanticInsights").doc("ins-1").get()
        );
    });

});

describe("semanticInsights — write access", () => {

    test("client cannot directly create a semanticInsight (server-only)", async () => {
        const db = dbAs("user-a");
        await assertFails(
            db.collection("users").doc("user-a").collection("semanticInsights").doc("new").set({
                term: "grace",
                definitionId: "def-1",
                visibility: "private",
                uid: "user-a",
            })
        );
    });

    test("owner can update allowed fields on their own insight", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            definitionId: "def-1",
            visibility: "private",
            uid: "user-a",
            userNote: null,
        });
        const db = dbAs("user-a");
        const { serverTimestamp } = require("firebase/firestore");
        await assertSucceeds(
            db.collection("users").doc("user-a")
                .collection("semanticInsights").doc("ins-1")
                .update({ userNote: "My study note", updatedAt: new Date() })
        );
    });

    test("owner cannot update restricted fields on their insight", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            definitionId: "def-1",
            visibility: "private",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertFails(
            db.collection("users").doc("user-a")
                .collection("semanticInsights").doc("ins-1")
                .update({ definitionId: "hacked-def", term: "evil" })
        );
    });

    test("other user cannot write to someone else's semanticInsights", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            uid: "user-a",
        });
        const db = dbAs("user-b");
        await assertFails(
            db.collection("users").doc("user-a")
                .collection("semanticInsights").doc("ins-1")
                .update({ userNote: "hijacked" })
        );
    });

    test("owner can delete their own insight", async () => {
        await seedDoc("users/user-a/semanticInsights/ins-1", {
            term: "grace",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a").collection("semanticInsights").doc("ins-1").delete()
        );
    });

});

// ── ─────────────────────────────────────────────────────────────────────────
// users/{uid}/knowledgeThreads — user-scoped, server-created
// ── ─────────────────────────────────────────────────────────────────────────

describe("knowledgeThreads — read access", () => {

    test("owner can read their own knowledgeThread", async () => {
        await seedDoc("users/user-a/knowledgeThreads/thread-1", {
            title: "Grace",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a").collection("knowledgeThreads").doc("thread-1").get()
        );
    });

    test("other user cannot read someone else's knowledgeThread", async () => {
        await seedDoc("users/user-a/knowledgeThreads/thread-1", {
            title: "Grace",
            uid: "user-a",
        });
        const db = dbAs("user-b");
        await assertFails(
            db.collection("users").doc("user-a").collection("knowledgeThreads").doc("thread-1").get()
        );
    });

});

describe("knowledgeThreads — write access", () => {

    test("client cannot directly create a knowledgeThread (server-only)", async () => {
        const db = dbAs("user-a");
        await assertFails(
            db.collection("users").doc("user-a").collection("knowledgeThreads").doc("new").set({
                title: "My Thread",
                uid: "user-a",
            })
        );
    });

    test("owner can update allowed fields on their thread", async () => {
        await seedDoc("users/user-a/knowledgeThreads/thread-1", {
            title: "Grace",
            sourceObjects: [],
            relatedScriptureRefs: [],
            savedInsightIds: [],
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a")
                .collection("knowledgeThreads").doc("thread-1")
                .update({ title: "Grace & Mercy", updatedAt: new Date() })
        );
    });

    test("other user cannot write to someone else's knowledgeThread", async () => {
        await seedDoc("users/user-a/knowledgeThreads/thread-1", {
            title: "Grace",
            uid: "user-a",
        });
        const db = dbAs("user-b");
        await assertFails(
            db.collection("users").doc("user-a")
                .collection("knowledgeThreads").doc("thread-1")
                .update({ title: "Hijacked" })
        );
    });

    test("owner can delete their own thread", async () => {
        await seedDoc("users/user-a/knowledgeThreads/thread-1", {
            title: "Grace",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a").collection("knowledgeThreads").doc("thread-1").delete()
        );
    });

});

// ── ─────────────────────────────────────────────────────────────────────────
// users/{uid}/presenceSignals — user-scoped, server-created, immutable
// ── ─────────────────────────────────────────────────────────────────────────

describe("presenceSignals — access", () => {

    test("owner can read their own presenceSignal", async () => {
        await seedDoc("users/user-a/presenceSignals/sig-1", {
            signalType: "scroll",
            privacyLevel: "aggregate",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a").collection("presenceSignals").doc("sig-1").get()
        );
    });

    test("other user cannot read someone else's presenceSignal", async () => {
        await seedDoc("users/user-a/presenceSignals/sig-1", {
            signalType: "scroll",
            uid: "user-a",
        });
        const db = dbAs("user-b");
        await assertFails(
            db.collection("users").doc("user-a").collection("presenceSignals").doc("sig-1").get()
        );
    });

    test("client cannot create a presenceSignal (server-only)", async () => {
        const db = dbAs("user-a");
        await assertFails(
            db.collection("users").doc("user-a").collection("presenceSignals").add({
                signalType: "scroll",
                privacyLevel: "aggregate",
                uid: "user-a",
            })
        );
    });

    test("client cannot update a presenceSignal (immutable)", async () => {
        await seedDoc("users/user-a/presenceSignals/sig-1", {
            signalType: "scroll",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertFails(
            db.collection("users").doc("user-a").collection("presenceSignals").doc("sig-1")
                .update({ signalType: "tampered" })
        );
    });

    test("owner can delete their own presenceSignal", async () => {
        await seedDoc("users/user-a/presenceSignals/sig-1", {
            signalType: "scroll",
            uid: "user-a",
        });
        const db = dbAs("user-a");
        await assertSucceeds(
            db.collection("users").doc("user-a").collection("presenceSignals").doc("sig-1").delete()
        );
    });

});

// ── ─────────────────────────────────────────────────────────────────────────
// Internal collections — _rateLimits, _semanticInFlight, _analyticsEvents
// ── ─────────────────────────────────────────────────────────────────────────

describe("internal collections — fully denied to clients", () => {

    test("client cannot read _rateLimits", async () => {
        const db = dbAs("user-a");
        await assertFails(db.collection("_rateLimits").doc("anything").get());
    });

    test("client cannot write _rateLimits", async () => {
        const db = dbAs("user-a");
        await assertFails(db.collection("_rateLimits").doc("anything").set({ x: 1 }));
    });

    test("client cannot read _semanticInFlight", async () => {
        const db = dbAs("user-a");
        await assertFails(db.collection("_semanticInFlight").doc("anything").get());
    });

    test("client cannot write _semanticInFlight", async () => {
        const db = dbAs("user-a");
        await assertFails(db.collection("_semanticInFlight").doc("anything").set({ x: 1 }));
    });

    test("client cannot read _analyticsEvents", async () => {
        const db = dbAs("user-a");
        await assertFails(db.collection("_analyticsEvents").doc("anything").get());
    });

    test("client cannot write _analyticsEvents", async () => {
        const db = dbAs("user-a");
        await assertFails(db.collection("_analyticsEvents").add({ event: "hijacked" }));
    });

});
