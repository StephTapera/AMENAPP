/**
 * gap-p0-sensitive-collections.rules.test.ts — GAP BOARD P0-10
 *
 * Emulator rules coverage for the 6 sensitive collections that previously had NO tests:
 *   crisisEscalations · userSafetyRecords · age_verification_events
 *   connectorTokens   · moderationQueue   · scheduledActions
 *
 * Loads repo-root firestore.rules (same file firebase.json deploys).
 * Per-collection design captured in the test descriptions; each test names the rule
 * it exercises so a future rule change that breaks one of these is immediately attributable.
 *
 * Run: cd Backend/rules-tests && npm test -- gap-p0-sensitive-collections
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  query,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-gap-p0-sensitive";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const OWNER = "owner-uid";
const OTHER = "other-uid";
const MODERATOR = "mod-uid";
const EXEC_ADMIN = "exec-uid";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync(RULES_PATH, "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
beforeEach(async () => { await testEnv.clearFirestore(); });
afterAll(async () => { await testEnv.cleanup(); });

const dbAs = (uid: string, claims: Record<string, unknown> = {}) =>
  testEnv.authenticatedContext(uid, { role: "member", ...claims }).firestore();
const dbAnon = () => testEnv.unauthenticatedContext().firestore();

async function seed(p: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), p), data); });
}

// ─── crisisEscalations ───────────────────────────────────────────────────────
// Rule: owner can read their own; exec_admin can read all; no client writes.
describe("crisisEscalations — crisis/safety records", () => {
  const PATH = `crisisEscalations/${OWNER}/2026-06-10T00:00:00Z`;

  beforeEach(async () => { await seed(PATH, { type: "crisis", uid: OWNER, createdAt: 0 }); });

  it("owner reads their own escalation", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER), PATH)));
  });

  it("exec_admin reads any escalation", async () => {
    await assertSucceeds(getDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH)));
  });

  it("random authenticated user CANNOT read crisis record", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER), PATH)));
  });

  it("anonymous user CANNOT read crisis record", async () => {
    await assertFails(getDoc(doc(dbAnon(), PATH)));
  });

  it("no client can CREATE a crisis escalation (CF only)", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), `crisisEscalations/${OWNER}/new-ts`),
      { type: "crisis", uid: OWNER }));
  });
});

// ─── userSafetyRecords ───────────────────────────────────────────────────────
// Rule: owner, moderator, exec_admin read; no client writes.
describe("userSafetyRecords — user safety assessment records", () => {
  const PATH = `userSafetyRecords/${OWNER}`;

  beforeEach(async () => { await seed(PATH, { riskScore: 12, uid: OWNER }); });

  it("owner reads their own safety record", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER), PATH)));
  });

  it("moderator reads safety record", async () => {
    await assertSucceeds(getDoc(doc(dbAs(MODERATOR, { role: "moderator" }), PATH)));
  });

  it("exec_admin reads safety record", async () => {
    await assertSucceeds(getDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH)));
  });

  it("other authenticated user CANNOT read safety record", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER), PATH)));
  });

  it("no client can WRITE a safety record (CF only)", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), PATH), { riskScore: 0, uid: OWNER }));
  });
});

// ─── age_verification_events ─────────────────────────────────────────────────
// Rule: ONLY exec_admin reads; no client writes (even owner cannot read own events).
describe("age_verification_events — COPPA verification audit trail", () => {
  const PATH = `age_verification_events/evt-001`;

  beforeEach(async () => { await seed(PATH, { userId: OWNER, type: "ageCollected", ageTier: "tierD" }); });

  it("exec_admin reads age verification events", async () => {
    await assertSucceeds(getDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH)));
  });

  it("even the subject owner CANNOT read age verification events (exec_admin only)", async () => {
    await assertFails(getDoc(doc(dbAs(OWNER), PATH)));
  });

  it("moderator CANNOT read age verification events", async () => {
    await assertFails(getDoc(doc(dbAs(MODERATOR, { role: "moderator" }), PATH)));
  });

  it("no client can WRITE age verification events (CF only)", async () => {
    await assertFails(setDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH),
      { userId: OWNER, type: "triggered" }));
  });
});

// ─── connectorTokens ─────────────────────────────────────────────────────────
// Rule: ALL reads AND writes are denied for every client (admin SDK only).
describe("connectorTokens — OAuth connector credentials (admin SDK only)", () => {
  const PATH = `connectorTokens/token-001`;

  beforeEach(async () => { await seed(PATH, { accessToken: "secret", uid: OWNER }); });

  it("exec_admin CANNOT read connector tokens (admin SDK only)", async () => {
    await assertFails(getDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH)));
  });

  it("owner CANNOT read their own connector token", async () => {
    await assertFails(getDoc(doc(dbAs(OWNER), PATH)));
  });

  it("anonymous user CANNOT read connector tokens", async () => {
    await assertFails(getDoc(doc(dbAnon(), PATH)));
  });

  it("no client can WRITE connector tokens (admin SDK only)", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), PATH), { accessToken: "x" }));
  });
});

// ─── moderationQueue ─────────────────────────────────────────────────────────
// Rule: moderator/pastor/owner/exec_admin reads; no client creates/deletes.
describe("moderationQueue — content moderation items", () => {
  const PATH = `moderationQueue/item-001`;

  beforeEach(async () => {
    await seed(PATH, { type: "post", orgId: "org-1", spaceId: "space-1", targetUid: OTHER });
  });

  it("moderator reads moderation queue", async () => {
    await assertSucceeds(getDoc(doc(dbAs(MODERATOR, { role: "moderator" }), PATH)));
  });

  it("executive_admin reads moderation queue", async () => {
    await assertSucceeds(getDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH)));
  });

  it("regular member CANNOT read moderation queue", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER), PATH)));
  });

  it("no client can CREATE moderation queue items (CF only)", async () => {
    await assertFails(setDoc(doc(dbAs(MODERATOR, { role: "moderator" }), `moderationQueue/new-item`),
      { type: "post" }));
  });

  it("no client can DELETE moderation queue items", async () => {
    await assertFails(deleteDoc(doc(dbAs(EXEC_ADMIN, { role: "executive_admin" }), PATH)));
  });
});

// ─── scheduledActions ────────────────────────────────────────────────────────
// Rule: owner reads own; owner creates (not minor, low-risk, dryRun=true);
//       owner updates (no server-only field mutations); no deletes.
describe("scheduledActions — Connected Intelligence scheduled work", () => {
  const ACTION_ID = "action-001";
  const PATH = `scheduledActions/${ACTION_ID}`;
  const VALID_CREATE = {
    uid: OWNER,
    writeRisk: "drafts_for_approval",
    dryRun: true,
    status: "dry_run",
    title: "Draft sermon notes",
    createdAt: Date.now(),
  };

  beforeEach(async () => { await seed(PATH, { ...VALID_CREATE, uid: OWNER }); });

  it("owner reads their own scheduled action", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER), PATH)));
  });

  it("other user CANNOT read scheduled actions", async () => {
    await assertFails(getDoc(doc(dbAs(OTHER), PATH)));
  });

  it("adult owner can CREATE a low-risk dry-run scheduled action", async () => {
    await assertSucceeds(setDoc(doc(dbAs(OWNER), `scheduledActions/new-action`), VALID_CREATE));
  });

  it("minor (tierB) CANNOT create scheduled action", async () => {
    await assertFails(setDoc(
      doc(dbAs(OWNER, { role: "member", ageTier: "tierB" }), `scheduledActions/minor-action`),
      VALID_CREATE
    ));
  });

  it("owner CANNOT create a non-dry-run action (dryRun must be true)", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), `scheduledActions/bad-action`), {
      ...VALID_CREATE, dryRun: false, status: "active",
    }));
  });

  it("owner CANNOT create a high-risk scheduled action (writeRisk not in allow-list)", async () => {
    await assertFails(setDoc(doc(dbAs(OWNER), `scheduledActions/risky-action`), {
      ...VALID_CREATE, writeRisk: "publish",
    }));
  });

  it("owner can UPDATE allowed fields (title)", async () => {
    await assertSucceeds(updateDoc(doc(dbAs(OWNER), PATH), { title: "Updated title" }));
  });

  it("owner CANNOT mutate server-only field lastRunAt on update", async () => {
    await assertFails(updateDoc(doc(dbAs(OWNER), PATH), { lastRunAt: Date.now() }));
  });

  it("no client can DELETE a scheduled action", async () => {
    await assertFails(deleteDoc(doc(dbAs(OWNER), PATH)));
  });
});
