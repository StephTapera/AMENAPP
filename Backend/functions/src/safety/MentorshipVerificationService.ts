/**
 * MentorshipVerificationService.ts
 *
 * Mentorship connection management and church/community verification for the
 * Amen Safety OS. Both systems produce positive trust signals that feed into
 * the progressive trust system via recordTrustEvent.
 *
 * Mentorship model:
 *   mentorshipConnections/{connectionId}
 *     mentorUid:   string
 *     menteeUid:   string
 *     status:      "pending" | "active" | "ended"
 *     requestedAt: Timestamp
 *     approvedAt?: Timestamp
 *     endedAt?:    Timestamp
 *     context?:    string   // e.g. "Bible study", "career mentorship"
 *
 * Church verification model:
 *   churchVerifications/{verificationId}
 *     uid:              string
 *     churchId:         string
 *     churchName:       string
 *     verificationCode: string
 *     status:           "pending" | "verified" | "revoked"
 *     verifiedAt?:      Timestamp
 *     createdAt:        Timestamp
 *
 *   churches/{churchId}
 *     name:                string
 *     adminUids:           string[]
 *     verificationEnabled: boolean
 *     createdAt:           Timestamp
 *
 *   churches/{churchId}/verificationCodes/{code}
 *     used:       boolean
 *     issuedBy:   string
 *     expiresAt:  Timestamp
 *     createdAt:  Timestamp
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

// eslint-disable-next-line
import { recordTrustEvent } from "./ProgressiveTrustService";
import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_ACTIVE_MENTORSHIPS_AS_MENTEE = 3;
const MAX_ACTIVE_MENTORSHIPS_AS_MENTOR = 10;
const MIN_MENTOR_TRUST_LEVEL = 2;
const DEFAULT_VERIFICATION_CODE_EXPIRY_HOURS = 48;

// ─── Types ────────────────────────────────────────────────────────────────────

export type MentorshipStatus = "pending" | "active" | "ended";
export type ChurchVerificationStatus = "pending" | "verified" | "revoked";

export interface MentorshipConnection {
  connectionId: string;
  mentorUid: string;
  menteeUid: string;
  status: MentorshipStatus;
  requestedAt: admin.firestore.Timestamp;
  approvedAt?: admin.firestore.Timestamp;
  endedAt?: admin.firestore.Timestamp;
  context?: string;
}

interface UserDoc {
  trustLevel?: number;
  accountStatus?: string;
  ageTier?: string;
}

interface ChurchDoc {
  name: string;
  adminUids: string[];
  verificationEnabled: boolean;
}

interface VerificationCodeDoc {
  used: boolean;
  issuedBy: string;
  expiresAt: admin.firestore.Timestamp;
  createdAt: admin.firestore.Timestamp;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Throws if a user's account is suspended or banned.
 */
async function assertAccountActive(uid: string, label: string): Promise<UserDoc> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", `User not found: ${label}.`);
  }
  const data = snap.data() as UserDoc;
  if (data.accountStatus === "suspended" || data.accountStatus === "banned") {
    throw new HttpsError(
      "failed-precondition",
      `Account is ${data.accountStatus}: ${label}.`
    );
  }
  return data;
}

/**
 * Counts active mentorship connections for a given uid and role field.
 */
async function countActiveConnections(
  field: "mentorUid" | "menteeUid",
  uid: string
): Promise<number> {
  const snap = await db
    .collection("mentorshipConnections")
    .where(field, "==", uid)
    .where("status", "==", "active")
    .get();
  return snap.size;
}

/**
 * Generates a cryptographically random 6-digit numeric code.
 */
function generate6DigitCode(): string {
  const value = Math.floor(100000 + Math.random() * 900000);
  return String(value);
}

// ─── requestMentorship ────────────────────────────────────────────────────────

/**
 * requestMentorship
 *
 * Mentee initiates a mentorship request to a mentor.
 * Input:  { mentorUid: string; context?: string }
 * Output: { connectionId: string; status: "pending" }
 */
export const requestMentorship = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<{ mentorUid: string; context?: string }>
  ): Promise<{ connectionId: string; status: "pending" }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const menteeUid = request.auth.uid;
    const { mentorUid, context } = request.data;

    // ── Input validation ──
    if (!mentorUid || typeof mentorUid !== "string" || mentorUid.trim() === "") {
      throw new HttpsError("invalid-argument", "mentorUid is required.");
    }
    if (mentorUid === menteeUid) {
      throw new HttpsError("invalid-argument", "Cannot request mentorship with yourself.");
    }
    if (context !== undefined && (typeof context !== "string" || context.trim() === "")) {
      throw new HttpsError("invalid-argument", "context must be a non-empty string if provided.");
    }

    // ── Account status checks ──
    const [mentorData, menteeData] = await Promise.all([
      assertAccountActive(mentorUid, "mentor"),
      assertAccountActive(menteeUid, "mentee"),
    ]);

    // ── Mentor trust level check ──
    const mentorTrustLevel = mentorData.trustLevel ?? 0;
    if (mentorTrustLevel < MIN_MENTOR_TRUST_LEVEL) {
      throw new HttpsError(
        "failed-precondition",
        `Mentor must have trust level ≥ ${MIN_MENTOR_TRUST_LEVEL}. Current: ${mentorTrustLevel}.`
      );
    }

    // ── Adult→minor guardian approval check ──
    const mentorAgeTier = mentorData.ageTier ?? "adult";
    const menteeAgeTier = menteeData.ageTier ?? "adult";
    const mentorIsAdult = !["minor", "teen"].includes(mentorAgeTier);
    const menteeIsMinor = ["minor", "teen"].includes(menteeAgeTier);
    if (mentorIsAdult && menteeIsMinor) {
      // Guardian approval required — not yet implemented; block for safety
      throw new HttpsError(
        "failed-precondition",
        "Adult-to-minor mentorship requires guardian approval, which is not yet enabled."
      );
    }

    // ── Connection limit checks ──
    const [menteeActiveCount, mentorActiveCount] = await Promise.all([
      countActiveConnections("menteeUid", menteeUid),
      countActiveConnections("mentorUid", mentorUid),
    ]);

    if (menteeActiveCount >= MAX_ACTIVE_MENTORSHIPS_AS_MENTEE) {
      throw new HttpsError(
        "resource-exhausted",
        `You may have at most ${MAX_ACTIVE_MENTORSHIPS_AS_MENTEE} active mentorships as a mentee.`
      );
    }
    if (mentorActiveCount >= MAX_ACTIVE_MENTORSHIPS_AS_MENTOR) {
      throw new HttpsError(
        "resource-exhausted",
        `This mentor already has the maximum of ${MAX_ACTIVE_MENTORSHIPS_AS_MENTOR} active mentorships.`
      );
    }

    // ── Duplicate check ──
    const existing = await db
      .collection("mentorshipConnections")
      .where("mentorUid", "==", mentorUid)
      .where("menteeUid", "==", menteeUid)
      .where("status", "in", ["pending", "active"])
      .limit(1)
      .get();

    if (!existing.empty) {
      const existingId = existing.docs[0].id;
      logger.info(`[MentorshipVerificationService] Duplicate request; returning existing connectionId=${existingId}`);
      return { connectionId: existingId, status: "pending" };
    }

    // ── Create connection ──
    const connRef = db.collection("mentorshipConnections").doc();
    const batch = db.batch();

    batch.set(connRef, {
      mentorUid,
      menteeUid,
      status: "pending",
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(context ? { context: context.trim() } : {}),
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    });

    // Notify mentor
    batch.set(
      db.collection("users").doc(mentorUid).collection("notifications").doc(),
      {
        type: "mentorship_request",
        menteeUid,
        connectionId: connRef.id,
        title: "Mentorship Request",
        body: context
          ? `Someone has requested mentorship from you: "${context.trim()}".`
          : "Someone has requested mentorship from you.",
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }
    );

    await batch.commit();

    logger.info(
      `[MentorshipVerificationService] requestMentorship connectionId=${connRef.id} mentorUid=${mentorUid} menteeUid=${menteeUid}`
    );
    return { connectionId: connRef.id, status: "pending" };
  }
);

// ─── approveMentorship ────────────────────────────────────────────────────────

/**
 * approveMentorship
 *
 * Mentor approves a pending mentorship request.
 * Input:  { connectionId: string }
 * Output: { success: boolean }
 */
export const approveMentorship = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<{ connectionId: string }>
  ): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const callerUid = request.auth.uid;
    const { connectionId } = request.data;

    if (!connectionId || typeof connectionId !== "string" || connectionId.trim() === "") {
      throw new HttpsError("invalid-argument", "connectionId is required.");
    }

    const connRef = db.collection("mentorshipConnections").doc(connectionId.trim());
    const connDoc = await connRef.get();

    if (!connDoc.exists) {
      throw new HttpsError("not-found", "Mentorship connection not found.");
    }

    const conn = connDoc.data() as MentorshipConnection & { policyVersion?: string };

    // Only the mentor may approve
    if (callerUid !== conn.mentorUid) {
      throw new HttpsError("permission-denied", "Only the mentor may approve this connection.");
    }

    if (conn.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        `Connection is already "${conn.status}"; cannot approve.`
      );
    }

    await connRef.update({
      status: "active",
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Record positive trust events for both parties
    await Promise.all([
      recordTrustEvent(conn.menteeUid, "mentorship_connection_approved"),
      recordTrustEvent(conn.mentorUid, "mentorship_connection_approved"),
    ]);

    logger.info(
      `[MentorshipVerificationService] approveMentorship connectionId=${connectionId} mentorUid=${conn.mentorUid} menteeUid=${conn.menteeUid}`
    );
    return { success: true };
  }
);

// ─── endMentorship ────────────────────────────────────────────────────────────

/**
 * endMentorship
 *
 * Either party may end an active or pending mentorship connection.
 * Input:  { connectionId: string }
 * Output: { success: boolean }
 */
export const endMentorship = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<{ connectionId: string }>
  ): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const callerUid = request.auth.uid;
    const { connectionId } = request.data;

    if (!connectionId || typeof connectionId !== "string" || connectionId.trim() === "") {
      throw new HttpsError("invalid-argument", "connectionId is required.");
    }

    const connRef = db.collection("mentorshipConnections").doc(connectionId.trim());
    const connDoc = await connRef.get();

    if (!connDoc.exists) {
      throw new HttpsError("not-found", "Mentorship connection not found.");
    }

    const conn = connDoc.data() as MentorshipConnection;

    if (callerUid !== conn.mentorUid && callerUid !== conn.menteeUid) {
      throw new HttpsError(
        "permission-denied",
        "Only the mentor or mentee may end this connection."
      );
    }

    if (conn.status === "ended") {
      throw new HttpsError("failed-precondition", "Connection has already ended.");
    }

    await connRef.update({
      status: "ended",
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(
      `[MentorshipVerificationService] endMentorship connectionId=${connectionId} by uid=${callerUid}`
    );
    return { success: true };
  }
);

// ─── getMyMentorships ─────────────────────────────────────────────────────────

/**
 * getMyMentorships
 *
 * Returns the caller's active mentorship connections.
 * Input:  { role?: "mentor" | "mentee" }  — defaults to both roles
 * Output: { connections: MentorshipConnection[] }
 */
export const getMyMentorships = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<{ role?: "mentor" | "mentee" }>
  ): Promise<{ connections: MentorshipConnection[] }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { role } = request.data;

    if (role !== undefined && role !== "mentor" && role !== "mentee") {
      throw new HttpsError("invalid-argument", "role must be \"mentor\" or \"mentee\" if provided.");
    }

    const fetchConnections = async (
      field: "mentorUid" | "menteeUid"
    ): Promise<MentorshipConnection[]> => {
      const snap = await db
        .collection("mentorshipConnections")
        .where(field, "==", uid)
        .where("status", "==", "active")
        .get();
      return snap.docs.map((doc) => ({
        connectionId: doc.id,
        ...(doc.data() as Omit<MentorshipConnection, "connectionId">),
      }));
    };

    let connections: MentorshipConnection[];

    if (role === "mentor") {
      connections = await fetchConnections("mentorUid");
    } else if (role === "mentee") {
      connections = await fetchConnections("menteeUid");
    } else {
      // Both roles
      const [asMentor, asMentee] = await Promise.all([
        fetchConnections("mentorUid"),
        fetchConnections("menteeUid"),
      ]);
      // Deduplicate by connectionId (no overlap expected, but be safe)
      const seen = new Set<string>();
      connections = [...asMentor, ...asMentee].filter((c) => {
        if (seen.has(c.connectionId)) return false;
        seen.add(c.connectionId);
        return true;
      });
    }

    logger.info(
      `[MentorshipVerificationService] getMyMentorships uid=${uid} role=${role ?? "both"} count=${connections.length}`
    );
    return { connections };
  }
);

// ─── requestChurchVerification ────────────────────────────────────────────────

/**
 * requestChurchVerification
 *
 * User submits a church-issued verification code to verify their church membership.
 * Input:  { churchId: string; verificationCode: string }
 * Output: { success: boolean; churchName: string }
 */
export const requestChurchVerification = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<{ churchId: string; verificationCode: string }>
  ): Promise<{ success: boolean; churchName: string }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { churchId, verificationCode } = request.data;

    // ── Input validation ──
    if (!churchId || typeof churchId !== "string" || churchId.trim() === "") {
      throw new HttpsError("invalid-argument", "churchId is required.");
    }
    if (
      !verificationCode ||
      typeof verificationCode !== "string" ||
      verificationCode.trim() === ""
    ) {
      throw new HttpsError("invalid-argument", "verificationCode is required.");
    }

    const normalizedCode = verificationCode.trim();
    const normalizedChurchId = churchId.trim();

    // ── Look up church ──
    const churchRef = db.collection("churches").doc(normalizedChurchId);
    const churchDoc = await churchRef.get();

    if (!churchDoc.exists) {
      throw new HttpsError("not-found", "Church not found.");
    }

    const church = churchDoc.data() as ChurchDoc;

    if (!church.verificationEnabled) {
      throw new HttpsError(
        "failed-precondition",
        "This church has not enabled member verification."
      );
    }

    // ── Validate verification code ──
    const codeRef = churchRef.collection("verificationCodes").doc(normalizedCode);
    const codeDoc = await codeRef.get();

    if (!codeDoc.exists) {
      throw new HttpsError("invalid-argument", "Invalid verification code.");
    }

    const codeData = codeDoc.data() as VerificationCodeDoc;
    const now = admin.firestore.Timestamp.now();

    if (codeData.used) {
      throw new HttpsError("already-exists", "This verification code has already been used.");
    }
    if (codeData.expiresAt.toMillis() <= now.toMillis()) {
      throw new HttpsError("deadline-exceeded", "This verification code has expired.");
    }

    // ── Check for existing active verification ──
    const existingVerif = await db
      .collection("churchVerifications")
      .where("uid", "==", uid)
      .where("churchId", "==", normalizedChurchId)
      .where("status", "==", "verified")
      .limit(1)
      .get();

    if (!existingVerif.empty) {
      throw new HttpsError(
        "already-exists",
        "You are already verified for this church."
      );
    }

    // ── Atomic write: create verification record + mark code used + update user ──
    const verifRef = db.collection("churchVerifications").doc();
    const batch = db.batch();

    batch.set(verifRef, {
      uid,
      churchId: normalizedChurchId,
      churchName: church.name,
      verificationCode: normalizedCode,
      status: "verified" as ChurchVerificationStatus,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    });

    batch.update(codeRef, { used: true });

    batch.update(db.collection("users").doc(uid), {
      verifiedChurchIds: admin.firestore.FieldValue.arrayUnion(normalizedChurchId),
    });

    await batch.commit();

    await recordTrustEvent(uid, "church_connection_verified");

    logger.info(
      `[MentorshipVerificationService] requestChurchVerification uid=${uid} churchId=${normalizedChurchId} verifId=${verifRef.id}`
    );
    return { success: true, churchName: church.name };
  }
);

// ─── issueChurchVerificationCode ──────────────────────────────────────────────

/**
 * issueChurchVerificationCode
 *
 * Church admin generates a one-time 6-digit verification code for distribution
 * to congregation members.
 * Input:  { churchId: string; expiresInHours?: number }
 * Output: { code: string; expiresAt: Timestamp }
 */
export const issueChurchVerificationCode = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<{ churchId: string; expiresInHours?: number }>
  ): Promise<{ code: string; expiresAt: admin.firestore.Timestamp }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const callerUid = request.auth.uid;
    const { churchId, expiresInHours } = request.data;

    // ── Input validation ──
    if (!churchId || typeof churchId !== "string" || churchId.trim() === "") {
      throw new HttpsError("invalid-argument", "churchId is required.");
    }

    let hoursUntilExpiry = DEFAULT_VERIFICATION_CODE_EXPIRY_HOURS;
    if (expiresInHours !== undefined) {
      if (
        typeof expiresInHours !== "number" ||
        !Number.isFinite(expiresInHours) ||
        expiresInHours <= 0 ||
        expiresInHours > 720
      ) {
        throw new HttpsError(
          "invalid-argument",
          "expiresInHours must be a positive number ≤ 720."
        );
      }
      hoursUntilExpiry = expiresInHours;
    }

    const normalizedChurchId = churchId.trim();

    // ── Verify caller is a church admin ──
    const churchRef = db.collection("churches").doc(normalizedChurchId);
    const churchDoc = await churchRef.get();

    if (!churchDoc.exists) {
      throw new HttpsError("not-found", "Church not found.");
    }

    const church = churchDoc.data() as ChurchDoc;

    if (!Array.isArray(church.adminUids) || !church.adminUids.includes(callerUid)) {
      throw new HttpsError(
        "permission-denied",
        "Only church admins may issue verification codes."
      );
    }

    // ── Generate a unique 6-digit code ──
    const now = new Date();
    const expiresAtDate = new Date(now.getTime() + hoursUntilExpiry * 60 * 60 * 1000);
    const expiresAt = admin.firestore.Timestamp.fromDate(expiresAtDate);

    // Retry up to 5 times to avoid collision with an existing unused code
    let code = "";
    let codeRef: admin.firestore.DocumentReference | null = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = generate6DigitCode();
      const candidateRef = churchRef.collection("verificationCodes").doc(candidate);
      const candidateDoc = await candidateRef.get();
      if (!candidateDoc.exists || (candidateDoc.data() as VerificationCodeDoc).used) {
        code = candidate;
        codeRef = candidateRef;
        break;
      }
    }

    if (!code || !codeRef) {
      throw new HttpsError(
        "resource-exhausted",
        "Could not generate a unique verification code. Please try again."
      );
    }

    await codeRef.set({
      used: false,
      issuedBy: callerUid,
      expiresAt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(
      `[MentorshipVerificationService] issueChurchVerificationCode churchId=${normalizedChurchId} issuedBy=${callerUid} expiresInHours=${hoursUntilExpiry}`
    );
    return { code, expiresAt };
  }
);

// ─── getChurchVerificationStatus ─────────────────────────────────────────────

/**
 * getChurchVerificationStatus
 *
 * Returns all verified church memberships for the authenticated user.
 * Input:  (none)
 * Output: { verifiedChurches: { churchId: string; churchName: string; verifiedAt: Timestamp }[] }
 */
export const getChurchVerificationStatus = onCall(
  { enforceAppCheck: true },
  async (
    request: CallableRequest<Record<string, never>>
  ): Promise<{
    verifiedChurches: {
      churchId: string;
      churchName: string;
      verifiedAt: admin.firestore.Timestamp;
    }[];
  }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;

    const snap = await db
      .collection("churchVerifications")
      .where("uid", "==", uid)
      .where("status", "==", "verified")
      .get();

    const verifiedChurches = snap.docs.map((doc) => {
      const data = doc.data() as {
        churchId: string;
        churchName: string;
        verifiedAt: admin.firestore.Timestamp;
      };
      return {
        churchId: data.churchId,
        churchName: data.churchName,
        verifiedAt: data.verifiedAt,
      };
    });

    logger.info(
      `[MentorshipVerificationService] getChurchVerificationStatus uid=${uid} count=${verifiedChurches.length}`
    );
    return { verifiedChurches };
  }
);
