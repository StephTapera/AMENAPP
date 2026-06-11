import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

/**
 * action-intelligence.rules.test.ts — Action Intelligence lane
 *
 * Pins the security invariants for the object collections written by the
 * `executeAmenAction` callable (Backend/functions/src/actionIntelligence.ts):
 *   - every collection is SERVER-AUTHORITATIVE: no client create/update/delete
 *   - reads are owner-scoped (and scope-member for shared graphs)
 *   - the audit log is fully opaque to clients
 *   - the per-user memory graph is strictly private
 *
 * NOTE ON RULES SOURCE: this suite loads the repo-root `firestore.rules` —
 * the file `firebase.json` actually deploys (tracked, AI collections present).
 * The rest of this harness strips `AMENAPP/firestore 18.rules` into
 * firestore.deploy.rules, but that source is UNTRACKED and currently lacks the
 * AI collections, so it would false-fail every owner-read here. Reconciling the
 * two rules files is the rules claimant's task (logged in AGENT_LANES.md).
 */

const PROJECT_ID = "amen-rules-test-action-intelligence";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const OWNER = "owner-uid";
const STRANGER = "stranger-uid";

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

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

function dbAnon() {
  return testEnv.unauthenticatedContext().firestore();
}

// Seed as admin (rules disabled) — mirrors how the callable writes server-side.
async function seed(pathParts: string[], data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), pathParts[0], ...pathParts.slice(1)), data);
  });
}

// ── actionIntelligenceObjects — owner-only read, no client write ──────────────

describe("actionIntelligenceObjects", () => {
  test("owner can read their own object", async () => {
    await seed(["actionIntelligenceObjects", "obj-1"], { ownerId: OWNER, objectClass: "need" });
    await assertSucceeds(getDoc(doc(dbAs(OWNER), "actionIntelligenceObjects", "obj-1")));
  });

  test("a different signed-in user cannot read someone else's object", async () => {
    await seed(["actionIntelligenceObjects", "obj-1"], { ownerId: OWNER, objectClass: "need" });
    await assertFails(getDoc(doc(dbAs(STRANGER), "actionIntelligenceObjects", "obj-1")));
  });

  test("anonymous user cannot read an object", async () => {
    await seed(["actionIntelligenceObjects", "obj-1"], { ownerId: OWNER, objectClass: "need" });
    await assertFails(getDoc(doc(dbAnon(), "actionIntelligenceObjects", "obj-1")));
  });

  test("client cannot create an object", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "actionIntelligenceObjects", "obj-new"), { ownerId: OWNER }));
  });

  test("owner cannot update their own object", async () => {
    await seed(["actionIntelligenceObjects", "obj-1"], { ownerId: OWNER, objectClass: "need" });
    await assertFails(updateDoc(doc(dbAs(OWNER), "actionIntelligenceObjects", "obj-1"), { objectClass: "moment" }));
  });

  test("owner cannot delete their own object", async () => {
    await seed(["actionIntelligenceObjects", "obj-1"], { ownerId: OWNER, objectClass: "need" });
    await assertFails(deleteDoc(doc(dbAs(OWNER), "actionIntelligenceObjects", "obj-1")));
  });
});

// ── actionIntelligenceAudit — fully opaque to clients ─────────────────────────

describe("actionIntelligenceAudit", () => {
  test("owner of the audited action cannot read the audit entry", async () => {
    await seed(["actionIntelligenceAudit", "audit-1"], { uid: OWNER, actionVerb: "pray_now" });
    await assertFails(getDoc(doc(dbAs(OWNER), "actionIntelligenceAudit", "audit-1")));
  });

  test("client cannot write an audit entry", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "actionIntelligenceAudit", "audit-new"), { uid: OWNER }));
  });
});

// ── users/{uid}/amenMemoryGraph — strictly private, no client write ───────────

describe("amenMemoryGraph", () => {
  test("owner can read their own memory node", async () => {
    await seed(["users", OWNER, "amenMemoryGraph", "mem-1"], { summary: "follow up" });
    await assertSucceeds(getDoc(doc(dbAs(OWNER), "users", OWNER, "amenMemoryGraph", "mem-1")));
  });

  test("another user cannot read someone else's memory node", async () => {
    await seed(["users", OWNER, "amenMemoryGraph", "mem-1"], { summary: "follow up" });
    await assertFails(getDoc(doc(dbAs(STRANGER), "users", OWNER, "amenMemoryGraph", "mem-1")));
  });

  test("owner cannot write their own memory node from the client", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "users", OWNER, "amenMemoryGraph", "mem-2"), { summary: "x" }));
  });
});

// ── amenVolunteerAssignments — owner or assignee read, no client write ────────

describe("amenVolunteerAssignments", () => {
  const ASSIGNEE = "assignee-uid";

  test("owner can read the assignment", async () => {
    await seed(["amenVolunteerAssignments", "asg-1"], { ownerId: OWNER, assigneeId: ASSIGNEE });
    await assertSucceeds(getDoc(doc(dbAs(OWNER), "amenVolunteerAssignments", "asg-1")));
  });

  test("assignee can read the assignment", async () => {
    await seed(["amenVolunteerAssignments", "asg-1"], { ownerId: OWNER, assigneeId: ASSIGNEE });
    await assertSucceeds(getDoc(doc(dbAs(ASSIGNEE), "amenVolunteerAssignments", "asg-1")));
  });

  test("an unrelated user cannot read the assignment", async () => {
    await seed(["amenVolunteerAssignments", "asg-1"], { ownerId: OWNER, assigneeId: ASSIGNEE });
    await assertFails(getDoc(doc(dbAs(STRANGER), "amenVolunteerAssignments", "asg-1")));
  });

  test("client cannot create an assignment", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "amenVolunteerAssignments", "asg-new"), { ownerId: OWNER, assigneeId: ASSIGNEE }));
  });
});

// ── amenRelationshipSignals — owner or target read, no client write ───────────

describe("amenRelationshipSignals", () => {
  const TARGET = "target-uid";

  test("owner can read the signal", async () => {
    await seed(["amenRelationshipSignals", "sig-1"], { ownerId: OWNER, targetUserId: TARGET });
    await assertSucceeds(getDoc(doc(dbAs(OWNER), "amenRelationshipSignals", "sig-1")));
  });

  test("target can read the signal", async () => {
    await seed(["amenRelationshipSignals", "sig-1"], { ownerId: OWNER, targetUserId: TARGET });
    await assertSucceeds(getDoc(doc(dbAs(TARGET), "amenRelationshipSignals", "sig-1")));
  });

  test("an unrelated user cannot read the signal", async () => {
    await seed(["amenRelationshipSignals", "sig-1"], { ownerId: OWNER, targetUserId: TARGET });
    await assertFails(getDoc(doc(dbAs(STRANGER), "amenRelationshipSignals", "sig-1")));
  });

  test("client cannot create a signal", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "amenRelationshipSignals", "sig-new"), { ownerId: OWNER, targetUserId: TARGET }));
  });
});

// ── amenInitiatives — owner read, unrelated denied, no client write ───────────
// Positive space/church/org scope reads are covered by those collections' own
// membership suites; here we pin owner-positive + stranger-negative.

describe("amenInitiatives", () => {
  test("owner can read their initiative", async () => {
    await seed(["amenInitiatives", "init-1"], { ownerId: OWNER, source: {} });
    await assertSucceeds(getDoc(doc(dbAs(OWNER), "amenInitiatives", "init-1")));
  });

  test("an unrelated user with no scope cannot read the initiative", async () => {
    await seed(["amenInitiatives", "init-1"], { ownerId: OWNER, source: {} });
    await assertFails(getDoc(doc(dbAs(STRANGER), "amenInitiatives", "init-1")));
  });

  test("client cannot create an initiative", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "amenInitiatives", "init-new"), { ownerId: OWNER, source: {} }));
  });

  test("client cannot create a milestone under an initiative", async () => {
    await seed(["amenInitiatives", "init-1"], { ownerId: OWNER, source: {} });
    await assertFails(setDoc(doc(dbAs(OWNER), "amenInitiatives", "init-1", "milestones", "m-1"), { title: "x" }));
  });
});

// ── amenKnowledgeGraph — owner read, unrelated denied, no client write ────────

describe("amenKnowledgeGraph", () => {
  test("owner can read their node", async () => {
    await seed(["amenKnowledgeGraph", "node-1"], { ownerId: OWNER, scopeType: "user" });
    await assertSucceeds(getDoc(doc(dbAs(OWNER), "amenKnowledgeGraph", "node-1")));
  });

  test("an unrelated user with no scope cannot read the node", async () => {
    await seed(["amenKnowledgeGraph", "node-1"], { ownerId: OWNER, scopeType: "user" });
    await assertFails(getDoc(doc(dbAs(STRANGER), "amenKnowledgeGraph", "node-1")));
  });

  test("client cannot create a node", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), "amenKnowledgeGraph", "node-new"), { ownerId: OWNER, scopeType: "user" }));
  });
});
