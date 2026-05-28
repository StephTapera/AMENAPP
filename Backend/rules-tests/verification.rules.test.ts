import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";
import { firestoreEmulator } from "./emulatorConfig";

const PROJECT_ID = "amen-rules-test-verification";
const RULES_PATH = path.resolve(__dirname, "../../AMENAPP/firestore.deploy.rules");

const OWNER_UID = "verification-owner";
const OTHER_UID = "verification-other";
const ADMIN_UID = "verification-admin";
const ORG_ID = "verification-org";

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

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", OWNER_UID), {
      uid: OWNER_UID,
      username: "owner",
      displayName: "Owner User",
      isPrivate: false,
      publicVerificationSummary: {
        emailVerified: true,
        phoneVerified: false,
        identityVerified: false,
        creatorVerified: false,
        safetyStanding: "active",
        visibleBadges: ["email_verified"],
      },
    });
    await setDoc(doc(db, "users", OTHER_UID), {
      uid: OTHER_UID,
      username: "other",
      displayName: "Other User",
      isPrivate: false,
    });
    await setDoc(doc(db, "users", OWNER_UID, "privateVerification", "main"), {
      provider: "mock",
      providerReferenceId: "provider-ref",
      identityVerified: true,
    });
    await setDoc(doc(db, "users", OWNER_UID, "verificationRequests", "request-1"), {
      type: "identity",
      status: "pending",
      createdAt: new Date(),
    });
    await setDoc(doc(db, "organizations", ORG_ID, "members", ADMIN_UID), {
      role: "admin",
      status: "active",
    });
    await setDoc(doc(db, "organizations", ORG_ID, "publicVerificationSummary", "main"), {
      organizationVerified: true,
      verifiedName: "Amen Test Church",
      visibleBadges: ["organization_verified"],
    });
    await setDoc(doc(db, "organizations", ORG_ID, "privateVerification", "main"), {
      domainChallengeHash: "hash",
    });
    await setDoc(doc(db, "organizations", ORG_ID, "roles", OWNER_UID), {
      role: "Pastor",
      status: "approved",
      scope: "main",
    });
    await setDoc(doc(db, "verificationAuditLogs", "audit-1"), {
      actorUid: ADMIN_UID,
      targetUid: OWNER_UID,
      action: "approved",
      createdAt: new Date(),
    });
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

function dbAs(uid: string, claims: Record<string, unknown> = {}) {
  return testEnv.authenticatedContext(uid, {
    email_verified: true,
    firebase: { sign_in_provider: "password" },
    ...claims,
  }).firestore();
}

describe("verification Firestore rules", () => {
  test("public user verification summary can be read but not spoofed by owner", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OTHER_UID), "users", OWNER_UID)));
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID), {
      publicVerificationSummary: {
        identityVerified: true,
        visibleBadges: ["identity_verified"],
      },
    }));
    await assertFails(updateDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID), {
      identityVerified: true,
    }));
  });

  test("private verification is owner/admin readable and never client writable", async () => {
    const ownerRef = doc(dbAs(OWNER_UID), "users", OWNER_UID, "privateVerification", "main");
    await assertSucceeds(getDoc(ownerRef));
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "users", OWNER_UID, "privateVerification", "main")));
    await assertSucceeds(getDoc(doc(dbAs(ADMIN_UID, { admin: true }), "users", OWNER_UID, "privateVerification", "main")));
    await assertFails(setDoc(ownerRef, { identityVerified: true }, { merge: true }));
  });

  test("verification requests are owner readable/create-only without server fields", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID, "verificationRequests", "request-1")));
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "users", OWNER_UID, "verificationRequests", "request-1")));
    await assertSucceeds(setDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID, "verificationRequests", "client-request"), {
      type: "creator",
      createdAt: new Date(),
    }));
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "users", OWNER_UID, "verificationRequests", "spoofed"), {
      type: "identity",
      status: "approved",
      createdAt: new Date(),
    }));
  });

  test("organization summaries are public, private org verification is admin-only, roles are scoped readable", async () => {
    await assertSucceeds(getDoc(doc(dbAs(OTHER_UID), "organizations", ORG_ID, "publicVerificationSummary", "main")));
    await assertFails(setDoc(doc(dbAs(OTHER_UID), "organizations", ORG_ID, "publicVerificationSummary", "main"), {
      organizationVerified: false,
    }, { merge: true }));
    await assertFails(getDoc(doc(dbAs(OTHER_UID), "organizations", ORG_ID, "privateVerification", "main")));
    await assertSucceeds(getDoc(doc(dbAs(ADMIN_UID), "organizations", ORG_ID, "privateVerification", "main")));
    await assertSucceeds(getDoc(doc(dbAs(OWNER_UID), "organizations", ORG_ID, "roles", OWNER_UID)));
    await assertFails(setDoc(doc(dbAs(ADMIN_UID), "organizations", ORG_ID, "roles", OWNER_UID), { status: "approved" }, { merge: true }));
  });

  test("audit logs are admin-readable and backend-only writable", async () => {
    await assertFails(getDoc(doc(dbAs(OWNER_UID), "verificationAuditLogs", "audit-1")));
    await assertSucceeds(getDoc(doc(dbAs(ADMIN_UID, { admin: true }), "verificationAuditLogs", "audit-1")));
    await assertFails(setDoc(doc(dbAs(ADMIN_UID, { admin: true }), "verificationAuditLogs", "client-audit"), {
      action: "tamper",
    }));
  });

  test("impersonation reports are create-only without reporterUid spoofing", async () => {
    await assertSucceeds(setDoc(doc(dbAs(OWNER_UID), "impersonationReports", "report-1"), {
      targetUid: OTHER_UID,
      reason: "This account is pretending to be me.",
      status: "open",
      createdAt: new Date(),
    }));
    await assertFails(setDoc(doc(dbAs(OWNER_UID), "impersonationReports", "report-2"), {
      targetUid: OTHER_UID,
      reporterUid: OWNER_UID,
      reason: "spoof",
      status: "open",
      createdAt: new Date(),
    }));
    await assertFails(getDoc(doc(dbAs(OWNER_UID), "impersonationReports", "report-1")));
  });
});
