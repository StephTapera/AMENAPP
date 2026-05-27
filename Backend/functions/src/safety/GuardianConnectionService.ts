/**
 * GuardianConnectionService.ts
 *
 * Parent/guardian connection management for Amen Safety OS.
 *
 * Allows parents/guardians to:
 *   - Send a connection request to a minor's account
 *   - Approve the connection from the minor's account
 *   - Receive safety alert notifications for high-risk interactions
 *   - Approve specific contacts to message the minor
 *   - View safety alerts for the connected minor
 *   - Remove the guardian connection
 *
 * Data model:
 *   guardianConnections/{connectionId}
 *     guardianUid: string
 *     minorUid: string
 *     status: "pending" | "active" | "revoked"
 *     requestedAt: Timestamp
 *     approvedAt?: Timestamp
 *
 *   users/{minorUid}.guardianUids: string[]  (for fast lookup in YouthSafetyService)
 *
 *   users/{guardianUid}/guardianAlerts/{alertId}
 *     alertType: string
 *     minorUid: string
 *     actorUid?: string
 *     readAt?: Timestamp
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type ConnectionStatus = "pending" | "active" | "revoked";

export interface GuardianConnection {
  connectionId: string;
  guardianUid: string;
  minorUid: string;
  status: ConnectionStatus;
  requestedAt: admin.firestore.Timestamp;
  approvedAt?: admin.firestore.Timestamp;
  revokedAt?: admin.firestore.Timestamp;
}

// ─── Request Guardian Connection ──────────────────────────────────────────────

/**
 * requestGuardianConnection
 *
 * Guardian initiates a connection request.
 * The minor (or their device) must approve via approveGuardianConnection.
 *
 * Input: { minorUid: string }
 */
export const requestGuardianConnection = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ minorUid: string }>): Promise<{ connectionId: string }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const guardianUid = request.auth.uid;
    const { minorUid } = request.data;

    if (!minorUid) throw new HttpsError("invalid-argument", "minorUid is required.");
    if (guardianUid === minorUid) throw new HttpsError("invalid-argument", "Cannot connect to your own account.");

    // Verify target is a minor account
    const minorDoc = await db.collection("users").doc(minorUid).get();
    const ageTier = minorDoc.data()?.ageTier;
    if (!["minor", "teen"].includes(ageTier ?? "")) {
      throw new HttpsError("failed-precondition", "Guardian connections are only for minor/teen accounts.");
    }

    // Check for duplicate active/pending connection
    const existing = await db.collection("guardianConnections")
      .where("guardianUid", "==", guardianUid)
      .where("minorUid", "==", minorUid)
      .where("status", "in", ["pending", "active"])
      .limit(1)
      .get();

    if (!existing.empty) {
      return { connectionId: existing.docs[0].id };
    }

    const ref = db.collection("guardianConnections").doc();
    await ref.set({
      guardianUid,
      minorUid,
      status: "pending",
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    });

    // Notify the minor's account of the pending request
    await db.collection("users").doc(minorUid).collection("notifications").add({
      type: "guardian_connection_request",
      guardianUid,
      connectionId: ref.id,
      title: "Guardian Connection Request",
      body: "A parent or guardian has requested to connect to your account.",
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[GuardianConnectionService] Request created connectionId=${ref.id}`);
    return { connectionId: ref.id };
  }
);

// ─── Approve Guardian Connection ─────────────────────────────────────────────

/**
 * approveGuardianConnection
 *
 * Called from the minor's account (or a guardian already connected) to approve.
 *
 * Input: { connectionId: string }
 */
export const approveGuardianConnection = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ connectionId: string }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const callerUid = request.auth.uid;
    const { connectionId } = request.data;
    if (!connectionId) throw new HttpsError("invalid-argument", "connectionId is required.");

    const connRef = db.collection("guardianConnections").doc(connectionId);
    const connDoc = await connRef.get();
    if (!connDoc.exists) throw new HttpsError("not-found", "Connection not found.");

    const conn = connDoc.data() as GuardianConnection & { policyVersion?: string };

    if (conn.status !== "pending") {
      throw new HttpsError("failed-precondition", "Connection is not in pending state.");
    }

    // Only the minor or an existing active guardian may approve
    const isMinor = callerUid === conn.minorUid;
    const existingGuardians: string[] = (await db.collection("users").doc(conn.minorUid).get()).data()?.guardianUids ?? [];
    const isExistingGuardian = existingGuardians.includes(callerUid);
    const isAdmin = (request.auth.token as Record<string, unknown>).admin === true;

    if (!isMinor && !isExistingGuardian && !isAdmin) {
      throw new HttpsError("permission-denied", "Only the minor or an existing guardian may approve this connection.");
    }

    const batch = db.batch();

    // Mark connection active
    batch.update(connRef, {
      status: "active",
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Add guardian to minor's guardianUids array
    batch.update(db.collection("users").doc(conn.minorUid), {
      guardianUids: admin.firestore.FieldValue.arrayUnion(conn.guardianUid),
    });

    // Notify guardian of approval
    batch.set(db.collection("users").doc(conn.guardianUid).collection("notifications").doc(), {
      type: "guardian_connection_approved",
      minorUid: conn.minorUid,
      connectionId,
      title: "Guardian Connection Approved",
      body: "Your guardian connection request has been approved.",
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
    logger.info(`[GuardianConnectionService] Connection approved connectionId=${connectionId}`);
    return { success: true };
  }
);

// ─── Revoke Guardian Connection ───────────────────────────────────────────────

export const revokeGuardianConnection = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ connectionId: string }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const callerUid = request.auth.uid;
    const { connectionId } = request.data;
    if (!connectionId) throw new HttpsError("invalid-argument", "connectionId is required.");

    const connRef = db.collection("guardianConnections").doc(connectionId);
    const connDoc = await connRef.get();
    if (!connDoc.exists) throw new HttpsError("not-found", "Connection not found.");

    const conn = connDoc.data() as GuardianConnection;

    if (callerUid !== conn.guardianUid && callerUid !== conn.minorUid) {
      const isAdmin = (request.auth.token as Record<string, unknown>).admin === true;
      if (!isAdmin) throw new HttpsError("permission-denied", "Only parties to the connection may revoke it.");
    }

    const batch = db.batch();
    batch.update(connRef, {
      status: "revoked",
      revokedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("users").doc(conn.minorUid), {
      guardianUids: admin.firestore.FieldValue.arrayRemove(conn.guardianUid),
    });
    await batch.commit();

    logger.info(`[GuardianConnectionService] Connection revoked connectionId=${connectionId}`);
    return { success: true };
  }
);

// ─── Approve Specific Contact for Minor ───────────────────────────────────────

/**
 * approveContactForMinor
 * Guardian explicitly whitelists an account to DM the connected minor.
 */
export const approveContactForMinor = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ minorUid: string; contactUid: string }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");

    const guardianUid = request.auth.uid;
    const { minorUid, contactUid } = request.data;

    if (!minorUid || !contactUid) throw new HttpsError("invalid-argument", "minorUid and contactUid are required.");

    // Verify active guardian connection
    const connSnap = await db.collection("guardianConnections")
      .where("guardianUid", "==", guardianUid)
      .where("minorUid", "==", minorUid)
      .where("status", "==", "active")
      .limit(1)
      .get();

    if (connSnap.empty) {
      throw new HttpsError("permission-denied", "No active guardian connection found.");
    }

    await db.collection("users").doc(minorUid).collection("guardianApprovedContacts").doc(contactUid).set({
      approvedByGuardian: guardianUid,
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);

// ─── Deliver Safety Alert to Guardians ────────────────────────────────────────

/**
 * Called by YouthSafetyService and other components to deliver safety alerts
 * to all active guardians of a minor.
 */
export async function deliverSafetyAlertToGuardians(
  minorUid: string,
  alertType: string,
  actorUid?: string,
  contextId?: string
): Promise<void> {
  const minorDoc = await db.collection("users").doc(minorUid).get();
  const guardianUids: string[] = minorDoc.data()?.guardianUids ?? [];

  if (guardianUids.length === 0) return;

  const batch = db.batch();
  for (const guardianUid of guardianUids) {
    const alertRef = db.collection("users").doc(guardianUid).collection("guardianAlerts").doc();
    batch.set(alertRef, {
      alertType,
      minorUid,
      actorUid: actorUid ?? null,
      contextId: contextId ?? null,
      read: false,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Also write to guardian's notification feed
    const notifRef = db.collection("users").doc(guardianUid).collection("notifications").doc();
    batch.set(notifRef, {
      type: "guardian_safety_alert",
      alertType,
      minorUid,
      title: "Safety Alert",
      body: "A safety event was detected involving your connected account.",
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  try {
    await batch.commit();
  } catch (err) {
    logger.error("[GuardianConnectionService] Failed to deliver safety alerts.", err);
  }
}

// ─── Trigger: Forward Youth Safety Alerts to Guardians ───────────────────────

/**
 * When a youth safety alert document is written, forward it to guardians.
 */
export const forwardYouthAlertToGuardians = onDocumentWritten(
  "users/{minorUid}/safety/{alertId}",
  async (event) => {
    const data = event.data?.after.data();
    if (!data) return;

    const minorUid = event.params.minorUid;
    const alertType: string = data.alertType ?? "unknown";
    const actorUid: string | undefined = data.actorUid;
    const contextId: string | undefined = data.contextId;

    const HIGH_RISK_ALERT_TYPES = [
      "adult_dm_attempt_to_minor",
      "adult_follow_attempt_to_minor",
      "dm_attempted_to_minor_with_dm_off",
      "minor_safety_pattern",
    ];

    if (!HIGH_RISK_ALERT_TYPES.includes(alertType)) return;

    await deliverSafetyAlertToGuardians(minorUid, alertType, actorUid, contextId);
  }
);
