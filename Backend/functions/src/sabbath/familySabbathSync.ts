/**
 * familySabbathSync.ts — Sabbath Mode
 * Firebase gen2 HTTPS callable. Auth + AppCheck required.
 *
 * MINOR GATE: ANY member who is a minor → STOP, write nothing for entire sync.
 * Presence is BOOLEAN only — never a count.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();

async function resolveMemberList(
  spaceId: string | undefined,
  familyGroupId: string | undefined,
  callerUid: string
): Promise<string[]> {
  const groupId = spaceId ?? familyGroupId;
  if (!groupId) return [callerUid];

  const membersSnap = await db.collection("spaces").doc(groupId).collection("members").get();
  if (membersSnap.empty) return [callerUid];
  return membersSnap.docs.map((doc) => doc.id);
}

async function isMinorUser(uid: string): Promise<boolean> {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) return false;

  const data = userSnap.data() as {
    isMinor?: boolean;
    ageTier?: string;
    dateOfBirth?: admin.firestore.Timestamp | string | Date;
  };

  if (data.isMinor === true) return true;
  const tier = data.ageTier ?? "";
  if (tier === "under_minimum" || tier === "teen") return true;

  if (data.dateOfBirth) {
    let dob: Date | null = null;
    if (data.dateOfBirth instanceof admin.firestore.Timestamp) {
      dob = data.dateOfBirth.toDate();
    } else if (typeof data.dateOfBirth === "string") {
      dob = new Date(data.dateOfBirth);
    } else if (data.dateOfBirth instanceof Date) {
      dob = data.dateOfBirth;
    }
    if (dob) {
      const ageYears = (Date.now() - dob.getTime()) / (1000 * 60 * 60 * 24 * 365.25);
      if (ageYears < 18) return true;
    }
  }

  return false;
}

export const syncFamilySabbathPresence = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated.");

    const callerUid = request.auth.uid;
    const { spaceId, familyGroupId } = (request.data ?? {}) as {
      spaceId?: string;
      familyGroupId?: string;
    };

    // MINOR GATE — check caller first
    if (await isMinorUser(callerUid)) {
      return { MINOR_GATE_REQUIRED: true, stoppedAt: callerUid, reason: "minor account detected — caller is a minor" };
    }

    let memberIds: string[];
    try {
      memberIds = await resolveMemberList(spaceId, familyGroupId, callerUid);
    } catch (err) {
      console.error("[familySabbathSync] Failed to resolve members:", err);
      throw new HttpsError("internal", "Failed to resolve family member list.");
    }

    // MINOR GATE — check ALL members before ANY write
    for (const memberId of memberIds) {
      if (await isMinorUser(memberId)) {
        console.log(`[familySabbathSync] MINOR_GATE at memberId=${memberId} — writing nothing.`);
        return { MINOR_GATE_REQUIRED: true, stoppedAt: memberId, reason: "minor account detected" };
      }
    }

    // All adults — write boolean presence only, never a count
    const nowMs = Date.now();
    const batch = db.batch();

    for (const memberId of memberIds) {
      const presenceRef = db.collection("users").doc(memberId).collection("sabbath").doc("presence");
      batch.set(presenceRef, { resting: true, updatedAt: nowMs }, { merge: true });
    }

    const groupId = spaceId ?? familyGroupId;
    if (groupId) {
      const spaceRef = db.collection("spaces").doc(groupId);
      batch.set(spaceRef, { sabbathPresence: { adultsResting: true, updatedAt: nowMs } }, { merge: true });
    }

    await batch.commit();
    console.log(`[familySabbathSync] Synced presence for ${memberIds.length} adult(s) callerUid=${callerUid}`);

    // memberCount is logged server-side only — clients MUST NOT display this number
    return { success: true, memberCount: memberIds.length };
  }
);
