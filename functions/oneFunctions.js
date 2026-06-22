/**
 * oneFunctions.js
 * ONE — Private Social OS Cloud Functions
 * All callables require Firebase Auth + App Check.
 * Evidence lock runs BEFORE decay (invariant — never reorder).
 *
 * Deploy: firebase deploy --only functions:one_sendMoment,one_expireMoment,
 *           one_reportMoment,one_requestWitness,one_relayMoment,
 *           one_activateRepairFlow,one_acceptRepairFlow,
 *           one_verifyEntitlement,one_activateLegacy
 *
 * PREREQUISITE: Switch Firebase console App Check from "debug" → "enforce"
 * before deploying to external users.
 */

"use strict";

const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const db = () => admin.firestore();

// ── Helpers ───────────────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

function requireField(data, field) {
  if (!data[field]) {
    throw new HttpsError("invalid-argument", `Missing required field: ${field}`);
  }
  return data[field];
}

// Merge ConsentDNA: take the stricter of two permission sets.
// Mirrors ONEStickyConsentService.mergedConsentDNA on the server.
function mergePermissions(source, relay) {
  return {
    forwardAllowed:    source.forwardAllowed    && relay.forwardAllowed,
    saveAllowed:       source.saveAllowed        && relay.saveAllowed,
    quoteAllowed:      source.quoteAllowed       && relay.quoteAllowed,
    reactAllowed:      source.reactAllowed       && relay.reactAllowed,
    translateAllowed:  source.translateAllowed   && relay.translateAllowed,
    summarizeAllowed:  source.summarizeAllowed   && relay.summarizeAllowed,
    aiTrainingAllowed: source.aiTrainingAllowed  && relay.aiTrainingAllowed,
  };
}

// ── one_sendMoment ────────────────────────────────────────────────────────────

exports.one_sendMoment = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const { momentID, privacyContract, isRelay, sourceMomentID } = request.data;

  if (!momentID) throw new HttpsError("invalid-argument", "momentID required.");

  // If this is a relay, enforce ConsentDNA: caller cannot loosen source permissions.
  if (isRelay && sourceMomentID) {
    const sourceSnap = await db().collection("one_moments").doc(sourceMomentID).get();
    if (!sourceSnap.exists) {
      throw new HttpsError("not-found", "Source moment not found.");
    }
    const sourcePerms = sourceSnap.data().consentDNA?.permissions;
    if (sourcePerms && !sourcePerms.forwardAllowed) {
      throw new HttpsError(
        "permission-denied",
        "Source moment's ConsentDNA prohibits relay."
      );
    }
    // Apply merged ConsentDNA — stricter of source and relay contract wins.
    const relayPerms = privacyContract?.permissions ?? {};
    const merged = mergePermissions(sourcePerms ?? {}, relayPerms);
    if (!privacyContract) {
      throw new HttpsError("invalid-argument", "privacyContract required for relay.");
    }
    privacyContract.permissions = merged;
  }

  await db().collection("one_moments").doc(momentID).set({
    authorUID:     uid,
    privacyContract: privacyContract ?? null,
    consentDNA: {
      momentID,
      authorUID: uid,
      permissions: privacyContract?.permissions ?? {
        forwardAllowed: false, saveAllowed: false, quoteAllowed: false,
        reactAllowed: true, translateAllowed: true,
        summarizeAllowed: false, aiTrainingAllowed: false,
      },
      issuedAt: admin.firestore.FieldValue.serverTimestamp(),
      consentVersion: "1.0",
    },
    evidenceLocked: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { momentID };
});

// ── one_expireMoment ──────────────────────────────────────────────────────────

exports.one_expireMoment = onCall({ enforceAppCheck: true }, async (request) => {
  requireAuth(request);
  const momentID = requireField(request.data, "momentID");

  const momentRef = db().collection("one_moments").doc(momentID);
  const snap = await momentRef.get();

  if (!snap.exists) return; // Already deleted.

  // INVARIANT: Evidence lock blocks decay. Never reorder this check.
  if (snap.data().evidenceLocked === true) {
    // Evidence is under review. Do not decay.
    return { skipped: true, reason: "evidence_locked" };
  }

  await momentRef.delete();
  return { deleted: true };
});

// ── one_reportMoment ──────────────────────────────────────────────────────────

exports.one_reportMoment = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const momentID = requireField(request.data, "momentID");
  const reason   = request.data.reason ?? "unspecified";

  const momentRef  = db().collection("one_moments").doc(momentID);
  const evidenceID = db().collection("one_evidence").doc().id;

  await db().runTransaction(async (txn) => {
    const momentSnap = await txn.get(momentRef);

    // 1. Lock evidence FIRST — write to immutable evidence store.
    //    This must happen before any decay check. Invariant.
    txn.set(db().collection("one_evidence").doc(evidenceID), {
      evidenceID,
      momentID,
      reporterUID:   uid,
      reason,
      content:       momentSnap.exists ? momentSnap.data() : null,
      lockedAt:      admin.firestore.FieldValue.serverTimestamp(),
      retainUntil:   admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 90 * 24 * 60 * 60 * 1000) // 90 days
      ),
      status:        "pending_review",
    });

    // 2. Set evidenceLocked on the moment — decay CF will skip this moment.
    if (momentSnap.exists) {
      txn.update(momentRef, {
        evidenceLocked: true,
        reportedAt:     admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  // 3. Enqueue to moderation queue for human review.
  await db().collection("one_moderationQueue").add({
    evidenceID,
    momentID,
    reporterUID: uid,
    reason,
    queuedAt:    admin.firestore.FieldValue.serverTimestamp(),
    status:      "pending",
  });

  return { evidenceID };
});

// ── one_requestWitness ────────────────────────────────────────────────────────

exports.one_requestWitness = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const targetUID   = requireField(request.data, "targetUID");
  const seasonLabel = request.data.seasonLabel ?? "indefinite";

  const requestID = db().collection("one_witnessRequests").doc().id;
  await db().collection("one_witnessRequests").doc(requestID).set({
    requestID,
    fromUID:     uid,
    toUID:       targetUID,
    seasonLabel,
    status:      "pending",
    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { requestID };
});

// ── one_relayMoment ───────────────────────────────────────────────────────────

exports.one_relayMoment = onCall({ enforceAppCheck: true }, async (request) => {
  const uid      = requireAuth(request);
  const momentID = requireField(request.data, "momentID");
  const toUIDs   = request.data.toUIDs ?? [];

  const budgetRef = db().collection("one_reachBudgets").doc(uid);
  let sharesRemaining = 0;

  await db().runTransaction(async (txn) => {
    const budgetSnap  = await txn.get(budgetRef);
    const momentSnap  = await txn.get(db().collection("one_moments").doc(momentID));

    if (!momentSnap.exists) {
      throw new HttpsError("not-found", "Moment not found.");
    }

    const budget     = budgetSnap.exists ? budgetSnap.data() : { sharesRemaining: 20, chainDepth: 0 };
    const chainDepth = (momentSnap.data().chainDepth ?? 0) + 1;

    if (budget.sharesRemaining <= 0) {
      throw new HttpsError("resource-exhausted", "Weekly relay budget exhausted.");
    }
    if (chainDepth > 5) {
      throw new HttpsError("resource-exhausted", "Maximum relay chain depth reached.");
    }

    sharesRemaining = budget.sharesRemaining - 1;

    txn.set(budgetRef, { sharesRemaining, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    txn.update(db().collection("one_moments").doc(momentID), { chainDepth });
  });

  return { sharesRemaining };
});

// ── one_activateRepairFlow ────────────────────────────────────────────────────

exports.one_activateRepairFlow = onCall({ enforceAppCheck: true }, async (request) => {
  const uid      = requireAuth(request);
  const otherUID = requireField(request.data, "otherUID");

  const flowID = db().collection("one_repairFlows").doc().id;
  await db().collection("one_repairFlows").doc(flowID).set({
    flowID,
    participants:   [uid, otherUID],
    initiatorUID:   uid,
    phase:          "invited",
    invitedAt:      admin.firestore.FieldValue.serverTimestamp(),
    acceptedUIDs:   [uid],  // initiator pre-accepted
    toneCheckCount: 0,
  });

  return { flowID };
});

// ── one_acceptRepairFlow ──────────────────────────────────────────────────────

exports.one_acceptRepairFlow = onCall({ enforceAppCheck: true }, async (request) => {
  const uid    = requireAuth(request);
  const flowID = requireField(request.data, "flowID");

  const flowRef = db().collection("one_repairFlows").doc(flowID);
  await db().runTransaction(async (txn) => {
    const snap = await txn.get(flowRef);
    if (!snap.exists) throw new HttpsError("not-found", "Repair flow not found.");

    const data = snap.data();
    if (!data.participants.includes(uid)) {
      throw new HttpsError("permission-denied", "You are not a participant in this flow.");
    }

    const acceptedUIDs = Array.from(new Set([...data.acceptedUIDs, uid]));
    const bothAccepted = data.participants.every((p) => acceptedUIDs.includes(p));

    txn.update(flowRef, {
      acceptedUIDs,
      phase:      bothAccepted ? "active" : "invited",
      activatedAt: bothAccepted ? admin.firestore.FieldValue.serverTimestamp() : null,
    });
  });

  return {};
});

// ── one_verifyEntitlement ─────────────────────────────────────────────────────
// Reads the entitlement tier from Firestore (written by App Store Server
// Notification webhook). Client should call this after every verified
// StoreKit Transaction to refresh the server-side record.
// Never downgrade on network failure — client keeps cached entitlement.

exports.one_verifyEntitlement = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);

  const snap = await db().collection("one_users").doc(uid).get();
  if (!snap.exists) {
    // New user — free tier
    return { tier: "free", validUntilTimestamp: null };
  }

  const entitlement = snap.data().entitlement ?? {};
  return {
    tier:                entitlement.tier ?? "free",
    validUntilTimestamp: entitlement.validUntil
      ? entitlement.validUntil.toMillis() / 1000
      : null,
  };
});

// ── one_activateLegacy ────────────────────────────────────────────────────────
// Trustee-only. Verifies that the caller is a named trustee with canActivate=true
// before activating the directive.

exports.one_activateLegacy = onCall({ enforceAppCheck: true }, async (request) => {
  const uid         = requireAuth(request);
  const directiveID = requireField(request.data, "directiveID");

  const directiveRef = db().collection("one_legacyDirectives").doc(directiveID);
  await db().runTransaction(async (txn) => {
    const snap = await txn.get(directiveRef);
    if (!snap.exists) throw new HttpsError("not-found", "Directive not found.");

    const data     = snap.data();
    const trustees = data.trustees ?? [];

    // Verify caller is a trustee with canActivate=true.
    const trustee = trustees.find((t) => t.uid === uid && t.canActivate === true);
    if (!trustee) {
      throw new HttpsError(
        "permission-denied",
        "You are not authorized to activate this directive."
      );
    }

    if (data.activatedAt) {
      throw new HttpsError("already-exists", "This directive has already been activated.");
    }

    txn.update(directiveRef, {
      activatedAt:    admin.firestore.FieldValue.serverTimestamp(),
      activatedByUID: uid,
      phase:          "activated",
    });
  });

  // Enqueue bequest delivery (time-release items scheduled separately).
  const directive = (await directiveRef.get()).data();
  for (const bequest of (directive.bequests ?? [])) {
    await db().collection("one_bequestQueue").add({
      directiveID,
      vaultItemID:    bequest.vaultItemID,
      recipientUID:   bequest.recipientUID,
      deliverAt:      bequest.deliverAt,
      message:        bequest.message ?? null,
      status:         "scheduled",
      enqueuedAt:     admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return { activated: true };
});
