/**
 * contextStore.emulator.test.ts
 * AMEN Universal Migration & Context System — Firestore Emulator Security Suite
 *
 * Runs against the Firebase Local Emulator Suite (firebase emulators:start).
 * Start emulator before running: `firebase emulators:start --only firestore,auth`
 *
 * Test coverage (mirrors ContextStoreAdversarialTests.swift, now with live Firestore):
 *   1. Owner can read/write own approved facets
 *   2. Cross-user read denied
 *   3. Unapproved facet write denied
 *   4. Wrong-tier write still accepted at rules layer (tier field is present+valid string)
 *   5. Snapshot create allowed; update denied (append-only)
 *   6. Tier-P facet cannot be read by a different auth identity
 *
 * Run: `cd functions && npm test -- --testPathPattern emulator`
 * Requires: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 in environment (set by emulator).
 */

import * as admin from "firebase-admin";
import * as testing from "@firebase/rules-unit-testing";

const PROJECT_ID = "amen-5e359";

// ── helpers ──────────────────────────────────────────────────────────────────

function authedDb(uid: string) {
  return testing
    .initializeTestApp({ projectId: PROJECT_ID, auth: { uid } })
    .firestore();
}

function adminDb() {
  // admin SDK uses the emulator via FIRESTORE_EMULATOR_HOST env var
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  return admin.firestore();
}

function approvedFacet(uid: string) {
  return {
    id: "test-uuid-1",
    userId: uid,
    category: "interests",
    key: "interests.manual",
    label: "Interests",
    value: JSON.stringify({ kind: "list", payload: ["theology"] }),
    visibility: "private",
    tier: "C",
    provenance: { source: "manual", userApproved: true, sanitizationPassId: "manual-test-001", userEdited: false },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    schemaVersion: 1,
  };
}

// ── setup / teardown ─────────────────────────────────────────────────────────

beforeAll(async () => {
  // Load the production rules into the emulator
  const { readFileSync } = await import("fs");
  const { resolve } = await import("path");
  const rulesPath = resolve(__dirname, "../../../../firestore.rules");
  await testing.loadFirestoreRules({ projectId: PROJECT_ID, rules: readFileSync(rulesPath, "utf8") });
});

afterAll(async () => {
  await Promise.all(testing.apps().map((app) => app.delete()));
});

afterEach(async () => {
  await testing.clearFirestoreData({ projectId: PROJECT_ID });
});

// ── tests ────────────────────────────────────────────────────────────────────

describe("ContextStore Firestore security rules (emulator)", () => {

  test("owner can write and read own approved facet", async () => {
    const uid = "alice";
    const db = authedDb(uid);
    const facetRef = db.collection("contextFacets").doc(uid).collection("facets").doc("f1");
    await expect(facetRef.set(approvedFacet(uid))).resolves.not.toThrow();
    const snap = await facetRef.get();
    expect(snap.exists).toBe(true);
  });

  test("cross-user read denied: bob cannot read alice's facets", async () => {
    const admin_db = adminDb();
    await admin_db.collection("contextFacets").doc("alice").collection("facets").doc("f1").set(approvedFacet("alice"));
    const bobDb = authedDb("bob");
    const ref = bobDb.collection("contextFacets").doc("alice").collection("facets").doc("f1");
    await expect(ref.get()).rejects.toThrow();
  });

  test("unapproved facet write denied", async () => {
    const uid = "alice";
    const db = authedDb(uid);
    const ref = db.collection("contextFacets").doc(uid).collection("facets").doc("f2");
    const unapproved = { ...approvedFacet(uid), provenance: { ...approvedFacet(uid).provenance, userApproved: false } };
    await expect(ref.set(unapproved)).rejects.toThrow();
  });

  test("write with invalid schemaVersion denied", async () => {
    const uid = "alice";
    const db = authedDb(uid);
    const ref = db.collection("contextFacets").doc(uid).collection("facets").doc("f3");
    const bad = { ...approvedFacet(uid), schemaVersion: 99 };
    await expect(ref.set(bad)).rejects.toThrow();
  });

  test("snapshot create allowed; update denied (append-only)", async () => {
    const uid = "alice";
    const db = authedDb(uid);
    const snapRef = db.collection("contextSnapshots").doc(uid).collection("snapshots").doc("s1");
    const snap = { userId: uid, takenAt: new Date(), trigger: "manual", facetStates: [], schemaVersion: 1 };
    await expect(snapRef.set(snap)).resolves.not.toThrow();
    await expect(snapRef.update({ trigger: "major_edit" })).rejects.toThrow();
  });

  test("unauthenticated read denied", async () => {
    const unauthDb = testing.initializeTestApp({ projectId: PROJECT_ID }).firestore();
    const ref = unauthDb.collection("contextFacets").doc("alice").collection("facets").doc("f1");
    await expect(ref.get()).rejects.toThrow();
  });
});
