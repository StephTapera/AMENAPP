import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "amen-rules-test-connect";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore 18.rules");

const OWNER_UID = "owner-uid";
const MEMBER_UID = "member-uid";
const UNPAID_UID = "unpaid-uid";
const NON_MEMBER_UID = "non-member-uid";
const SPACE_ID = "space-1";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "connectSpaces", SPACE_ID), {
      name: "Connect Space",
      visibility: "publicToSpace",
      moderationStatus: "allowed",
      safetyStatus: "allowed",
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "members", OWNER_UID), { role: "owner", status: "active" });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "members", MEMBER_UID), { role: "member", status: "active" });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "members", UNPAID_UID), { role: "member", status: "active" });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "channels", "general"), {
      name: "general",
      visibility: "publicToSpace",
      allowedRoles: ["owner", "member"],
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "channels", "private"), {
      name: "private",
      visibility: "privateGroup",
      allowedRoles: ["owner"],
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-1"), {
      body: "hello",
      deletedAt: null,
      aiExcluded: false,
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-excluded"), {
      body: "excluded",
      deletedAt: null,
      aiExcluded: true,
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-deleted"), {
      body: "deleted",
      deletedAt: new Date(),
      aiExcluded: false,
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "boards", "paid-board"), {
      title: "Paid",
      visibility: "paidTier",
      requiredTierId: "tier-pro",
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "boards", "confidential-board"), {
      title: "Confidential",
      visibility: "confidential",
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "boards", "youth-board"), {
      title: "Youth",
      visibility: "youthProtected",
    });
    await setDoc(doc(db, "connectMemberships", `${MEMBER_UID}_tier-pro`), {
      userId: MEMBER_UID,
      tierId: "tier-pro",
      membershipStatus: "active",
      paymentState: "paid",
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "marketplaceListings", "listing-approved"), {
      title: "Safe listing",
      moderationStatus: "approved",
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "marketplaceListings", "listing-pending"), {
      title: "Pending listing",
      moderationStatus: "pending",
    });
    await setDoc(doc(db, "connectCreatorProfiles", "creator-1"), {
      displayName: "Creator",
      safetyStatus: "allowed",
    });
    await setDoc(doc(db, "connectCreatorProfiles", "creator-1", "products", "paid-product"), {
      title: "Paid product",
      visibility: "paid",
      requiredTierId: "tier-pro",
    });
    await setDoc(doc(db, "connectPurchases", "purchase-1"), {
      userId: MEMBER_UID,
      purchaseState: "paid",
    });
    await setDoc(doc(db, "connectSpaces", SPACE_ID, "auditLogs", "audit-1"), {
      actorId: OWNER_UID,
      action: "seed",
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("Amen Connect Firestore rules", () => {
  test("unauthenticated read and write denied", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "connectSpaces", SPACE_ID)));
    await assertFails(setDoc(doc(db, "connectSpaces", "new-space"), { name: "x" }));
  });

  test("member read access allowed and non-member denied", async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    const nonMemberDb = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-1")));
    await assertFails(getDoc(doc(nonMemberDb, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-1")));
  });

  test("owner/admin access allowed and private channel denied to normal member", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID).firestore();
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(ownerDb, "connectSpaces", SPACE_ID, "channels", "private")));
    await assertFails(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "channels", "private")));
  });

  test("paid tier content denied for unpaid and allowed for paid member", async () => {
    const paidDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    const unpaidDb = testEnv.authenticatedContext(UNPAID_UID).firestore();
    await assertSucceeds(getDoc(doc(paidDb, "connectSpaces", SPACE_ID, "boards", "paid-board")));
    await assertFails(getDoc(doc(unpaidDb, "connectSpaces", SPACE_ID, "boards", "paid-board")));
  });

  test("youth-protected and confidential content denied to normal member", async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "boards", "youth-board")));
    await assertFails(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "boards", "confidential-board")));
  });

  test("AI-excluded and deleted messages are not client-readable for summary paths", async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-excluded")));
    await assertFails(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "channels", "general", "messages", "msg-deleted")));
  });

  test("client cannot write server-authoritative fields or audit logs", async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(setDoc(doc(ownerDb, "connectSpaces", SPACE_ID, "channels", "general", "messages", "client-msg"), {
      body: "client",
      moderationStatus: "allowed",
      safetyStatus: "allowed",
    }));
    await assertFails(updateDoc(doc(ownerDb, "connectSpaces", SPACE_ID, "members", MEMBER_UID), { role: "admin" }));
    await assertFails(setDoc(doc(ownerDb, "connectSpaces", SPACE_ID, "auditLogs", "client-audit"), { action: "client" }));
  });

  test("client cannot write payment state, trust badges, purchase state, or payouts", async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(setDoc(doc(memberDb, "connectMemberships", "client-membership"), { userId: MEMBER_UID, paymentState: "paid" }));
    await assertFails(setDoc(doc(memberDb, "connectCreatorProfiles", "client-creator"), { trustBadges: ["Identity Verified"] }));
    await assertFails(setDoc(doc(memberDb, "connectPurchases", "client-purchase"), { userId: MEMBER_UID, purchaseState: "paid" }));
    await assertFails(setDoc(doc(memberDb, "connectPayouts", "client-payout"), { userId: MEMBER_UID, payoutState: "paid" }));
  });

  test("marketplace visibility, creator profile access, membership access, and purchase protection", async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    const otherDb = testEnv.authenticatedContext(NON_MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "marketplaceListings", "listing-approved")));
    await assertFails(getDoc(doc(memberDb, "connectSpaces", SPACE_ID, "marketplaceListings", "listing-pending")));
    await assertSucceeds(getDoc(doc(memberDb, "connectCreatorProfiles", "creator-1")));
    await assertSucceeds(getDoc(doc(memberDb, "connectMemberships", `${MEMBER_UID}_tier-pro`)));
    await assertFails(getDoc(doc(otherDb, "connectMemberships", `${MEMBER_UID}_tier-pro`)));
    await assertFails(updateDoc(doc(memberDb, "connectPurchases", "purchase-1"), { purchaseState: "refunded" }));
  });
});
