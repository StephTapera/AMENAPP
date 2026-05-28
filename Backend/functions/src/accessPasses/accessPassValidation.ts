// accessPassValidation.ts — Pass status and eligibility validation

import * as admin from "firebase-admin";
import { AmenAccessPass, AmenAccessMode, RESTRICTED_DIRECT_JOIN_TYPES } from "./accessPassTypes";
import { verifyToken } from "./accessPassToken";
import * as functions from "firebase-functions";

const db = admin.firestore();

/**
 * Load and validate an access pass by ID.
 * Throws HttpsError with the appropriate code and a safe error code in message.
 */
export async function loadAndValidatePass(
  accessPassId: string,
  rawToken: string
): Promise<AmenAccessPass> {
  const passRef = db.collection("accessPasses").doc(accessPassId);
  const passSnap = await passRef.get();

  if (!passSnap.exists) {
    throw new functions.https.HttpsError("not-found", "invalid-pass");
  }

  const pass = passSnap.data() as AmenAccessPass;

  // Verify token before checking status (fail-safe ordering)
  if (!verifyToken(rawToken, pass.tokenHash)) {
    throw new functions.https.HttpsError("permission-denied", "invalid-pass");
  }

  const now = admin.firestore.Timestamp.now();

  // Check status
  if (pass.status === "revoked") {
    throw new functions.https.HttpsError("permission-denied", "revoked");
  }
  if (pass.status === "expired") {
    throw new functions.https.HttpsError("permission-denied", "expired");
  }
  if (pass.status === "paused") {
    throw new functions.https.HttpsError("unavailable", "paused");
  }

  // Check time windows
  if (pass.startsAt && pass.startsAt.toMillis() > now.toMillis()) {
    throw new functions.https.HttpsError("failed-precondition", "not-started");
  }
  if (pass.expiresAt && pass.expiresAt.toMillis() < now.toMillis()) {
    // Auto-mark expired
    await passRef.update({ status: "expired", "audit.updatedAt": now });
    throw new functions.https.HttpsError("permission-denied", "expired");
  }

  return pass;
}

/** Check if mode is allowed for a given target type (sensitive space protection). */
export function validateModeForTarget(
  mode: AmenAccessMode,
  targetType: string,
  isSensitive: boolean
): void {
  if (mode === "join" && RESTRICTED_DIRECT_JOIN_TYPES.includes(targetType as any)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "sensitive-direct-join-blocked"
    );
  }
  if (mode === "join" && isSensitive) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "sensitive-direct-join-blocked"
    );
  }
}

/** Check per-user usage limits. */
export async function checkMaxUsesPerUser(
  pass: AmenAccessPass,
  uid: string
): Promise<void> {
  if (!pass.maxUsesPerUser || pass.maxUsesPerUser <= 0) return;

  const eventsRef = db
    .collection("accessPasses")
    .doc(pass.accessPassId)
    .collection("events");

  const userEventsSnap = await eventsRef
    .where("uid", "==", uid)
    .where("type", "in", ["joined", "checkedIn"])
    .count()
    .get();

  if (userEventsSnap.data().count >= pass.maxUsesPerUser) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "max-uses-per-user-exceeded"
    );
  }
}

/** Check global max uses. Must be called inside a transaction. */
export function checkMaxUses(pass: AmenAccessPass): void {
  if (pass.maxUses !== undefined && pass.usesCount >= pass.maxUses) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "max-uses-exceeded"
    );
  }
}

/** Verify user eligibility for role-gated passes. */
export async function verifyRoleGatedEligibility(
  pass: AmenAccessPass,
  uid: string,
  userEmail?: string
): Promise<void> {
  // Check allowed member UIDs
  if (pass.allowedMemberUids && pass.allowedMemberUids.length > 0) {
    if (!pass.allowedMemberUids.includes(uid)) {
      throw new functions.https.HttpsError("permission-denied", "role-restricted");
    }
    return;
  }

  // Check allowed email domains
  if (pass.allowedEmailDomains && pass.allowedEmailDomains.length > 0 && userEmail) {
    const domain = userEmail.split("@")[1] ?? "";
    if (!pass.allowedEmailDomains.includes(domain)) {
      throw new functions.https.HttpsError("permission-denied", "role-restricted");
    }
    return;
  }

  // Check allowed role IDs
  if (pass.allowedRoleIds && pass.allowedRoleIds.length > 0) {
    // Check user's roles in the target's membership/role collection
    const memberSnap = await db
      .collection(`${pass.targetType}s`)
      .doc(pass.targetId)
      .collection("members")
      .doc(uid)
      .get();

    const memberData = memberSnap.data();
    const userRole: string = memberData?.role ?? "";

    if (!pass.allowedRoleIds.includes(userRole)) {
      throw new functions.https.HttpsError("permission-denied", "role-restricted");
    }
    return;
  }

  // No restrictions configured — pass is open within role-gated mode
}

/** Check if user is already a member of the target. */
export async function checkIfAlreadyMember(
  targetType: string,
  targetId: string,
  uid: string
): Promise<boolean> {
  try {
    const memberRef = db
      .collection(`${targetType}s`)
      .doc(targetId)
      .collection("members")
      .doc(uid);
    const snap = await memberRef.get();
    return snap.exists;
  } catch {
    return false;
  }
}

/** Check if user has a pending request for this pass. */
export async function checkIfRequestPending(
  accessPassId: string,
  uid: string
): Promise<boolean> {
  const requestsSnap = await db
    .collection("accessRequests")
    .where("accessPassId", "==", accessPassId)
    .where("requesterUid", "==", uid)
    .where("status", "==", "pending")
    .limit(1)
    .get();

  return !requestsSnap.empty;
}
