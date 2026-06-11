/**
 * gap-p0-dm-and-minor.rules.test.ts — GAP BOARD P0-1 + P0-3 (NEW, additive)
 *
 * Proves two deployed-rules holes are closed in repo-root firestore.rules:
 *
 *   P0-1  Conversations were gated on `participantUids`, a field the iOS client
 *         NEVER writes (it writes `participantIds`). Every DM read/create/list +
 *         message read/create was therefore DENIED. These tests use the REAL
 *         `participantIds` field and would FAIL against the pre-fix rules
 *         (participant denied) — they PASS only once the rules read participantIds.
 *
 *   P0-3  isMinor()/isUnderMinimum() checked the legacy tier strings
 *         'teen'/'under_minimum' which the age system NEVER emits. The real
 *         vocabulary is blocked(<13)/tierB(13-15)/tierC(16-17)/tierD(18+). Under
 *         the pre-fix rules a tierB/tierC minor was treated as an adult, so a minor
 *         could open an unsafe DM with no mutual-follow. These tests use the REAL
 *         tier strings and would FAIL against the pre-fix rules (minor allowed
 *         through) — they PASS only once isMinor() recognises blocked/tierB/tierC.
 *
 * Loads the SAME repo-root firestore.rules that firebase.json deploys.
 * Run: cd Backend/rules-tests && npm test -- gap-p0-dm-and-minor
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-gap-p0-dm-minor";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ME = "me-uid";          // adult member requester
const ADULT = "adult-uid";    // non-minor recipient
const STRANGER = "stranger-uid";
const MINOR_B = "minorB-uid";  // tierB minor (13-15)
const MINOR_C = "minorC-uid";  // tierC minor (16-17)
const BLOCKED = "blocked-uid"; // under-13 (COPPA blocked)

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync(RULES_PATH, "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
beforeEach(async () => { await testEnv.clearFirestore(); });
afterAll(async () => { await testEnv.cleanup(); });

// Default claim role is member; pass ageTier in claims for minor requesters.
const dbAs = (uid: string, claims: Record<string, unknown> = { role: "member" }) =>
  testEnv.authenticatedContext(uid, claims).firestore();

async function seed(p: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), p), data); });
}
async function seedUser(uid: string, ageTier: string) { await seed(`users/${uid}`, { ageTier }); }
async function follow(a: string, b: string) { await seed(`follows_index/${a}_${b}`, { exists: true }); }
async function mutualFollow(a: string, b: string) { await follow(a, b); await follow(b, a); }

// Real client shape: participantIds (NOT participantUids).
function createConversation(db: ReturnType<typeof dbAs>, id: string, participants: string[]) {
  return setDoc(doc(db, `conversations/${id}`), {
    participantIds: participants,
    isGroup: false,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  });
}

// ───────────────────────────── P0-1 : DM reachability ─────────────────────────
describe("P0-1 — conversations gate on participantIds (the field the client writes)", () => {
  it("participant can READ a conversation keyed by participantIds", async () => {
    await seed(`conversations/c1`, { participantIds: [ME, ADULT], isGroup: false });
    await assertSucceeds(getDoc(doc(dbAs(ME), `conversations/c1`)));
  });

  it("non-participant is DENIED read", async () => {
    await seed(`conversations/c1`, { participantIds: [ME, ADULT], isGroup: false });
    await assertFails(getDoc(doc(dbAs(STRANGER), `conversations/c1`)));
  });

  it("participant can CREATE a conversation (adult recipient, no minor gate)", async () => {
    await seedUser(ADULT, "tierD");
    await assertSucceeds(createConversation(dbAs(ME), "c2", [ME, ADULT]));
  });

  it("non-participant CANNOT create a conversation they are not in", async () => {
    await seedUser(ADULT, "tierD");
    await assertFails(createConversation(dbAs(STRANGER), "c3", [ME, ADULT]));
  });

  it("participant can SEND a message; non-participant cannot", async () => {
    await seed(`conversations/c4`, { participantIds: [ME, ADULT], isGroup: false });
    const sendAs = (uid: string) =>
      setDoc(doc(dbAs(uid), `conversations/c4/messages/m1`), { senderId: uid, text: "hi", createdAt: Date.now() });
    await assertSucceeds(sendAs(ME));
    await assertFails(setDoc(doc(dbAs(STRANGER), `conversations/c4/messages/m2`), { senderId: STRANGER, text: "x", createdAt: Date.now() }));
  });
});

// ───────────────────────────── P0-3 : real minor vocabulary ──────────────────
describe("P0-3 — minor gate recognises the real ageTier vocabulary", () => {
  it("tierB minor requester DM-ing an adult WITHOUT mutual follows is DENIED", async () => {
    await seedUser(ADULT, "tierD");
    // Pre-fix isMinor() was false for tierB → this create was wrongly ALLOWED.
    await assertFails(createConversation(dbAs(ME, { role: "member", ageTier: "tierB" }), "c5", [ME, ADULT]));
  });

  it("tierB minor requester DM-ing an adult WITH mutual follows is allowed", async () => {
    await seedUser(ADULT, "tierD");
    await mutualFollow(ME, ADULT);
    await assertSucceeds(createConversation(dbAs(ME, { role: "member", ageTier: "tierB" }), "c6", [ME, ADULT]));
  });

  it("under-13 'blocked' requester cannot create any conversation (isUnderMinimum)", async () => {
    await seedUser(ADULT, "tierD");
    await assertFails(createConversation(dbAs(ME, { role: "member", ageTier: "blocked" }), "c7", [ME, ADULT]));
  });

  it("adult DM-ing a tierC minor recipient requires mutual follows", async () => {
    await seedUser(MINOR_C, "tierC");
    await assertFails(createConversation(dbAs(ME), "c8", [ME, MINOR_C]));
    await mutualFollow(ME, MINOR_C);
    await assertSucceeds(createConversation(dbAs(ME), "c9", [ME, MINOR_C]));
  });

  it("adult DM-ing an under-13 'blocked' recipient is gated as a minor (isMinorAccount includes blocked)", async () => {
    await seedUser(BLOCKED, "blocked");
    // Pre-fix isMinorAccount() lacked 'blocked' → recipient treated as adult, create wrongly allowed.
    await assertFails(createConversation(dbAs(ME), "c10", [ME, BLOCKED]));
    await mutualFollow(ME, BLOCKED);
    await assertSucceeds(createConversation(dbAs(ME), "c11", [ME, BLOCKED]));
  });
});
