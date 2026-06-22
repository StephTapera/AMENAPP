/**
 * minor-safe-dm.rules.test.ts — [MINOR] DM safety matrix (NEW, additive)
 *
 * Verifies the conversation-create minor-safety gate in firestore.rules:
 *   allow create: ... && (!dmRequiresMinorSafety(participants) || twoPersonMinorSafeDM(participants))
 * where minor safety (when the OTHER participant is a minor) requires MUTUAL
 * follows_index edges (A→B AND B→A). Pre-reqs: signed-in, not under_minimum,
 * member-ish claim role, requester ∈ participantUids.
 *
 * Run with the existing harness: cd Backend/rules-tests && npm install && npm test
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-minor-safe-dm";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ME = "me-uid";        // the requester (adult member)
const MINOR = "minor-uid";  // a minor recipient
const ADULT = "adult-uid";  // a non-minor recipient

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync(RULES_PATH, "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
beforeEach(async () => { await testEnv.clearFirestore(); });
afterAll(async () => { await testEnv.cleanup(); });

const dbAs = (uid: string, claims: Record<string, unknown> = { role: "member" }) =>
  testEnv.authenticatedContext(uid, claims).firestore();
const dbAnon = () => testEnv.unauthenticatedContext().firestore();

async function seed(p: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => { await setDoc(doc(ctx.firestore(), p), data); });
}
async function seedUser(uid: string, ageTier: string) { await seed(`users/${uid}`, { ageTier }); }
async function follow(a: string, b: string) { await seed(`follows_index/${a}_${b}`, { exists: true }); }
async function mutualFollow(a: string, b: string) { await follow(a, b); await follow(b, a); }

function createConversation(db: ReturnType<typeof dbAs>, id: string, participants: string[]) {
  return setDoc(doc(db, `conversations/${id}`), {
    participantUids: participants,
    createdAt: Date.now(),
    lastMessage: "",
  });
}

describe("[MINOR] DM safety matrix — conversation create", () => {
  it("minorDM_nonMinorRecipient_allowed_withoutFollows", async () => {
    await seedUser(ADULT, "adult");
    await assertSucceeds(createConversation(dbAs(ME), "c1", [ME, ADULT]));
  });

  it("minorDM_minorRecipient_mutualFollows_allowed", async () => {
    await seedUser(MINOR, "teen");
    await mutualFollow(ME, MINOR);
    await assertSucceeds(createConversation(dbAs(ME), "c2", [ME, MINOR]));
  });

  it("minorDM_minorRecipient_onlyForwardEdge_denied", async () => {
    await seedUser(MINOR, "teen");
    await follow(ME, MINOR); // me→minor only
    await assertFails(createConversation(dbAs(ME), "c3", [ME, MINOR]));
  });

  it("minorDM_minorRecipient_onlyReverseEdge_denied", async () => {
    await seedUser(MINOR, "teen");
    await follow(MINOR, ME); // minor→me only
    await assertFails(createConversation(dbAs(ME), "c4", [ME, MINOR]));
  });

  it("minorDM_minorRecipient_noEdges_denied", async () => {
    await seedUser(MINOR, "teen");
    await assertFails(createConversation(dbAs(ME), "c5", [ME, MINOR]));
  });

  it("minorDM_signedOut_denied", async () => {
    await seedUser(ADULT, "adult");
    await assertFails(createConversation(dbAnon(), "c6", [ME, ADULT]));
  });

  it("minorDM_underMinimumSender_denied_evenWithMutualFollows", async () => {
    // Sender whose own ageTier is under_minimum cannot create DMs at all.
    await seedUser(MINOR, "teen");
    await mutualFollow(ME, MINOR);
    const dbUnderMin = dbAs(ME, { role: "member", ageTier: "under_minimum" });
    await assertFails(createConversation(dbUnderMin, "c7", [ME, MINOR]));
  });

  it("minorDM_noMemberRole_denied", async () => {
    // Visitor (no member-ish claim role) cannot create a conversation.
    await seedUser(ADULT, "adult");
    const dbVisitor = dbAs(ME, { role: "visitor" });
    await assertFails(createConversation(dbVisitor, "c8", [ME, ADULT]));
  });
});
