/**
 * permissionsCallables.ts
 *
 * Cloud Function callables for the Amen Permissions Engine.
 *
 * Exposed functions:
 *   setDateOfBirth          — records DOB, sets ageTier (teen/adult), triggers recompute
 *   setMode                 — validate + update identityMode + recompute PermissionSet
 *   initiateDM              — pairwise canMessage() check before opening a conversation
 *   requestGuardianConsent  — reserved for under-13 Family Mode release
 *   confirmGuardianConsent  — guardian confirms a link (7-day TTL); recomputes child permissions
 *   resolvePermissionsCallable — internal/debug; admin-only re-resolution for a uid
 *
 * Every callable re-resolves server-side before acting. The client PermissionSet
 * is UX-only — these functions are the enforcement layer.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import { AgeTier, IdentityMode, AccountSnapshot, PermissionSet } from "./permissionsTypes";
import {
  resolvePermissions,
  isModeAllowedForTier,
  canMessage,
} from "./permissionsEngine";
import { writeResolvedPermissions, snapshotFromDoc, ageInYears } from "./permissionsUtils";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── setMode ──────────────────────────────────────────────────────────────────

interface SetModeRequest {
  mode: IdentityMode;
}
interface SetModeResponse {
  success: boolean;
  permissions: PermissionSet;
}

/**
 * Updates the caller's identityMode if the mode is permitted for their age tier,
 * then recomputes and stores the resolved PermissionSet.
 */
export const setMode = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<SetModeRequest>): Promise<SetModeResponse> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { mode } = request.data;
    const validModes: IdentityMode[] = [
      "social", "discussion", "study", "quiet", "postless", "campus", "family",
    ];
    if (!mode || !validModes.includes(mode)) {
      throw new HttpsError("invalid-argument", `Invalid mode: "${mode}".`);
    }

    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "User document not found.");

    const account = snapshotFromDoc(uid, userSnap.data()!);

    if (!isModeAllowedForTier(mode, account.ageTier)) {
      throw new HttpsError(
        "permission-denied",
        `Mode "${mode}" is not permitted for age tier "${account.ageTier}".`
      );
    }

    // Persist the mode change and recompute atomically
    const updatedAccount: AccountSnapshot = { ...account, mode };
    const resolved = resolvePermissions(updatedAccount);

    await db.collection("users").doc(uid).update({ mode });
    await writeResolvedPermissions(uid, resolved, account.ageTier);

    logger.info(`[PermissionsEngine] setMode uid=${uid} mode=${mode}`);
    return { success: true, permissions: resolved };
  }
);

// ─── initiateDM ───────────────────────────────────────────────────────────────

interface InitiateDMRequest {
  targetUid: string;
}
interface InitiateDMResponse {
  allowed: boolean;
  reason?: string;
}

/**
 * Runs pairwise canMessage() check before creating a conversation.
 * Does NOT create the conversation — caller creates it only on allowed: true.
 */
export const initiateDM = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<InitiateDMRequest>): Promise<InitiateDMResponse> => {
    const senderUid = request.auth?.uid;
    if (!senderUid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { targetUid } = request.data;
    if (!targetUid) throw new HttpsError("invalid-argument", "targetUid is required.");
    if (targetUid === senderUid) {
      return { allowed: false, reason: "Cannot message yourself." };
    }

    const [senderSnap, recipientSnap, senderPermSnap, recipientPermSnap] = await Promise.all([
      db.collection("users").doc(senderUid).get(),
      db.collection("users").doc(targetUid).get(),
      db.collection("permissions").doc(senderUid).get(),
      db.collection("permissions").doc(targetUid).get(),
    ]);

    if (!senderSnap.exists || !recipientSnap.exists) {
      throw new HttpsError("not-found", "One or both user documents not found.");
    }

    const senderAccount = snapshotFromDoc(senderUid, senderSnap.data()!);
    const recipientAccount = snapshotFromDoc(targetUid, recipientSnap.data()!);

    // Fall back to live resolution if cached permissions are missing
    const senderPerms: PermissionSet = senderPermSnap.exists
      ? (senderPermSnap.data() as PermissionSet)
      : resolvePermissions(senderAccount);
    const recipientPerms: PermissionSet = recipientPermSnap.exists
      ? (recipientPermSnap.data() as PermissionSet)
      : resolvePermissions(recipientAccount);

    // Check trust edge and mutual connection from the social graph
    const [trustEdge, mutualConn] = await Promise.all([
      trustEdgeExists(senderUid, targetUid),
      mutualConnectionExists(senderUid, targetUid),
    ]);

    const allowed = canMessage(
      senderPerms,
      senderAccount.ageTier,
      recipientPerms,
      recipientAccount.ageTier,
      trustEdge,
      mutualConn
    );

    if (!allowed) {
      // Write a safety alert if an adult tried to contact a minor without clearance
      const recipientIsMinor = recipientAccount.ageTier !== "adult";
      if (recipientIsMinor && senderAccount.ageTier === "adult") {
        await writeDMAttemptAlert(senderUid, targetUid);
      }
      return { allowed: false, reason: "Messaging not permitted between these accounts." };
    }

    logger.info(`[PermissionsEngine] initiateDM sender=${senderUid} target=${targetUid} allowed=true`);
    return { allowed: true };
  }
);

// ─── requestGuardianConsent ───────────────────────────────────────────────────

interface RequestGuardianConsentRequest {
  guardianEmail: string;
}
interface RequestGuardianConsentResponse {
  success: boolean;
  linkId: string;
}

/**
 * Guardian consent entry point. Reserved for a future release — v1 ships teen/adult only.
 * When under-13 (Family Mode) ships, this function will create a pending guardianLinks
 * document, stamp a 7-day expiry, and queue an email to the guardian.
 * Until then it always rejects so clients surface a meaningful error instead of hanging.
 */
export const requestGuardianConsent = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<RequestGuardianConsentRequest>
  ): Promise<RequestGuardianConsentResponse> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");

    throw new HttpsError(
      "failed-precondition",
      "Guardian consent is not available in this version of the app."
    );
  }
);

// ─── confirmGuardianConsent ───────────────────────────────────────────────────

interface ConfirmGuardianConsentRequest {
  linkId: string;
}
interface ConfirmGuardianConsentResponse {
  success: boolean;
  childPermissions: PermissionSet;
}

/**
 * Guardian (authenticated) confirms a pending guardianLinks document.
 * Flips guardianConsentStatus to "confirmed" and recomputes child permissions.
 * The guardian must be authenticated as themselves (not as the child).
 */
export const confirmGuardianConsent = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<ConfirmGuardianConsentRequest>
  ): Promise<ConfirmGuardianConsentResponse> => {
    const guardianUid = request.auth?.uid;
    if (!guardianUid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { linkId } = request.data;
    if (!linkId) throw new HttpsError("invalid-argument", "linkId is required.");

    const linkRef = db.collection("guardianLinks").doc(linkId);
    const linkSnap = await linkRef.get();
    if (!linkSnap.exists) throw new HttpsError("not-found", "Guardian link not found.");

    const linkData = linkSnap.data()!;
    if (linkData.status !== "pending") {
      throw new HttpsError("failed-precondition", "This link has already been processed.");
    }

    if (linkData.linkExpiresAt && linkData.linkExpiresAt.toDate() < new Date()) {
      throw new HttpsError("deadline-exceeded", "This guardian consent link has expired.");
    }

    const guardianUser = await admin.auth().getUser(guardianUid);
    if (guardianUser.email !== linkData.guardianEmail) {
      throw new HttpsError(
        "permission-denied",
        "Authenticated account does not match the guardian email on this link."
      );
    }

    const { childUid } = linkData;
    const batch = db.batch();

    // Mark link confirmed
    batch.update(linkRef, {
      guardianUid,
      status: "confirmed",
      confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Update child's consent status and guardian list
    const childRef = db.collection("users").doc(childUid);
    batch.update(childRef, {
      guardianConsentStatus: "confirmed",
      guardianUids: admin.firestore.FieldValue.arrayUnion(guardianUid),
    });

    await batch.commit();

    // Recompute child permissions now that consent is confirmed
    const childSnap = await childRef.get();
    const childAccount = snapshotFromDoc(childUid, childSnap.data()!);
    const resolved = resolvePermissions(childAccount);
    await writeResolvedPermissions(childUid, resolved, childAccount.ageTier);

    logger.info(
      `[PermissionsEngine] confirmGuardianConsent guardian=${guardianUid} child=${childUid}`
    );
    return { success: true, childPermissions: resolved };
  }
);

// ─── setDateOfBirth ───────────────────────────────────────────────────────────

interface SetDateOfBirthRequest {
  /** ISO 8601 date string, e.g. "2005-06-15". */
  dateOfBirth: string;
}
interface SetDateOfBirthResponse {
  ageTier: AgeTier;
}

/**
 * Records the account's date of birth, derives the correct age tier (teen/adult),
 * and updates users/{uid}.ageTier — which triggers onUserWrite to recompute permissions.
 * Minimum age enforced: 13. Accounts younger than 13 are rejected (v1 does not support under-13).
 * DOB is stored in users/{uid}/private/safety.dateOfBirth (server Timestamp).
 */
export const setDateOfBirth = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<SetDateOfBirthRequest>): Promise<SetDateOfBirthResponse> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const { dateOfBirth } = request.data;
    if (!dateOfBirth) throw new HttpsError("invalid-argument", "dateOfBirth is required.");

    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateOfBirth)) {
      throw new HttpsError("invalid-argument", "dateOfBirth must be a YYYY-MM-DD string (e.g. '2005-06-15').");
    }
    const dob = new Date(dateOfBirth);
    if (isNaN(dob.getTime())) {
      throw new HttpsError("invalid-argument", "dateOfBirth is not a valid calendar date.");
    }

    const now = new Date();
    if (dob > now) {
      throw new HttpsError("invalid-argument", "dateOfBirth cannot be in the future.");
    }

    const age = ageInYears(dob, now);
    if (age < 13) {
      throw new HttpsError(
        "failed-precondition",
        "The minimum age to use this app is 13. Under-13 support is coming in a future release."
      );
    }

    const ageTier: AgeTier = age >= 18 ? "adult" : "teen";

    const batch = db.batch();

    // Write DOB to private subcollection (triggers nothing on its own)
    const safetyRef = db.collection("users").doc(uid).collection("private").doc("safety");
    batch.set(safetyRef, {
      dateOfBirth: admin.firestore.Timestamp.fromDate(dob),
      setAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Update ageTier on the root user document — triggers onUserWrite → permission recompute.
    // Use set+merge so this works for both existing docs and brand-new sign-up flows.
    const userRef = db.collection("users").doc(uid);
    batch.set(userRef, { ageTier }, { merge: true });

    await batch.commit();

    const userSnap = await userRef.get();
    if (!userSnap.exists) throw new HttpsError("not-found", "User document not found.");

    const account = snapshotFromDoc(uid, userSnap.data()!);
    const resolved = resolvePermissions(account);
    await writeResolvedPermissions(uid, resolved, account.ageTier);

    logger.info(`[PermissionsEngine] setDateOfBirth uid=${uid} ageTier=${ageTier} age=${age}`);
    return { ageTier };
  }
);

// ─── resolvePermissionsCallable ───────────────────────────────────────────────

interface ResolvePermissionsRequest {
  uid?: string;
}

/**
 * Internal/debug callable. Admin-only — re-resolves permissions for any uid.
 * Used for manual remediation and integration testing.
 */
export const resolvePermissionsCallable = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<ResolvePermissionsRequest>): Promise<PermissionSet> => {
    const callerUid = request.auth?.uid;
    if (!callerUid) throw new HttpsError("unauthenticated", "Authentication required.");

    const token = request.auth!.token as Record<string, unknown>;
    if (!token.admin) throw new HttpsError("permission-denied", "Admin access required.");

    const targetUid = request.data.uid ?? callerUid;
    const userSnap = await db.collection("users").doc(targetUid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");

    const account = snapshotFromDoc(targetUid, userSnap.data()!);
    const resolved = resolvePermissions(account);
    await writeResolvedPermissions(targetUid, resolved, account.ageTier);

    logger.info(`[PermissionsEngine] resolvePermissionsCallable uid=${targetUid} by=${callerUid}`);
    return resolved;
  }
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function trustEdgeExists(senderUid: string, targetUid: string): Promise<boolean> {
  const snap = await db
    .collection("trustEdges")
    .where("fromUid", "==", senderUid)
    .where("toUid", "==", targetUid)
    .where("active", "==", true)
    .limit(1)
    .get();
  return !snap.empty;
}

async function mutualConnectionExists(uidA: string, uidB: string): Promise<boolean> {
  const [aFollowsB, bFollowsA] = await Promise.all([
    db.collection("follows_index").doc(`${uidA}_${uidB}`).get(),
    db.collection("follows_index").doc(`${uidB}_${uidA}`).get(),
  ]);
  return aFollowsB.exists && bFollowsA.exists;
}

async function writeDMAttemptAlert(senderUid: string, targetUid: string): Promise<void> {
  try {
    const batch = db.batch();
    const alertRef = db.collection("users").doc(targetUid).collection("safety").doc();
    batch.set(alertRef, {
      alertType: "adult_dm_attempt_to_minor_no_permission",
      actorUid: senderUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const queueRef = db.collection("moderationQueue").doc();
    batch.set(queueRef, {
      type: "permissions_dm_block",
      senderUid,
      targetUid,
      priority: "high",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
  } catch (err) {
    logger.warn("[PermissionsEngine] Failed to write DM attempt alert.", err);
  }
}
