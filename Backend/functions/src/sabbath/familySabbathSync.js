/**
 * familySabbathSync.js
 * Phase 2C — Backend (Sabbath Mode)
 *
 * Firebase gen2 HTTPS callable.
 * Auth + App Check required.
 *
 * Callable name: syncFamilySabbathPresence
 *
 * Input: {
 *   spaceId?: string,
 *   familyGroupId?: string
 * }
 *
 * CRITICAL INVARIANTS (never relax):
 *
 *   MINOR GATE: ANY path that touches a minor account MUST return
 *               { MINOR_GATE_REQUIRED: true, stoppedAt: memberId, reason: '...' }
 *               immediately and write NOTHING for the entire sync operation.
 *               This is not a TODO — it is implemented and enforced here.
 *
 *   PRESENCE is BOOLEAN ONLY:
 *     - users/{memberId}/sabbath/presence = { resting: true, updatedAt: now }
 *     - spaces/{spaceId}/sabbathPresence = { adultsResting: true }
 *     "adultsResting: true" is a boolean signal — clients show text only, never numbers.
 *     NEVER write a count of how many members are resting.
 *
 *   All writes are additive (merge: true).
 *
 * OUTPUT:
 *   Success: { success: true, memberCount: <number_of_adults_synced> }
 *   Minor detected: { MINOR_GATE_REQUIRED: true, stoppedAt: <uid>, reason: string }
 *   No members: { success: true, memberCount: 0 }
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Resolve the member list from a Space or family group.
 * Returns an array of member UIDs.
 *
 * For a Space: reads spaces/{spaceId}/members subcollection.
 * For a familyGroupId: reads spaces/{familyGroupId}/members (same pattern —
 *   family groups are implemented as private Spaces in AMEN).
 *
 * @param {string|undefined} spaceId
 * @param {string|undefined} familyGroupId
 * @param {string} callerUid
 * @returns {Promise<string[]>}
 */
async function resolveMemberList(spaceId, familyGroupId, callerUid) {
  const groupId = spaceId || familyGroupId;

  if (!groupId) {
    // No group specified — sync only the caller
    return [callerUid];
  }

  const membersSnap = await db
    .collection("spaces")
    .doc(groupId)
    .collection("members")
    .get();

  if (membersSnap.empty) {
    return [callerUid];
  }

  return membersSnap.docs.map((doc) => doc.id);
}

/**
 * Check if a user is a minor.
 * Reads users/{uid} for dateOfBirth or isMinor flag.
 *
 * @param {string} uid
 * @returns {Promise<boolean>}
 */
async function isMinorUser(uid) {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) return false;

  const data = userSnap.data();

  // Explicit minor flag
  if (data.isMinor === true) return true;

  // Age tier claim stored on user document (mirror of custom claims)
  const ageTier = data.ageTier || "";
  if (ageTier === "under_minimum" || ageTier === "teen") return true;

  // dateOfBirth field — compute age
  if (data.dateOfBirth) {
    let dob;
    if (data.dateOfBirth.toDate) {
      // Firestore Timestamp
      dob = data.dateOfBirth.toDate();
    } else if (typeof data.dateOfBirth === "string") {
      dob = new Date(data.dateOfBirth);
    } else if (data.dateOfBirth instanceof Date) {
      dob = data.dateOfBirth;
    }

    if (dob) {
      const ageDays = (Date.now() - dob.getTime()) / (1000 * 60 * 60 * 24);
      const ageYears = ageDays / 365.25;
      // Under 18 is treated as minor for Sabbath family sync
      if (ageYears < 18) return true;
    }
  }

  return false;
}

// ---------------------------------------------------------------------------
// Callable
// ---------------------------------------------------------------------------

const syncFamilySabbathPresence = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    // Auth gate
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const callerUid = request.auth.uid;
    const { spaceId, familyGroupId } = request.data || {};

    // MINOR GATE on caller — if the caller themselves is a minor, stop immediately
    const callerIsMinor = await isMinorUser(callerUid);
    if (callerIsMinor) {
      // Write nothing — return immediately
      return {
        MINOR_GATE_REQUIRED: true,
        stoppedAt: callerUid,
        reason: "minor account detected — caller is a minor",
      };
    }

    // Resolve the member list
    let memberIds;
    try {
      memberIds = await resolveMemberList(spaceId, familyGroupId, callerUid);
    } catch (err) {
      console.error(`[familySabbathSync] Failed to resolve member list:`, err);
      throw new HttpsError("internal", "Failed to resolve family member list.");
    }

    // ------------------------------------------------------------------
    // CRITICAL: Check every member for minor status BEFORE any writes.
    // If ANY member is a minor → STOP, write nothing for the entire sync.
    // ------------------------------------------------------------------
    for (const memberId of memberIds) {
      const minor = await isMinorUser(memberId);
      if (minor) {
        // STOP immediately — do not write any presence data
        console.log(
          `[familySabbathSync] MINOR_GATE triggered at memberId=${memberId} — writing nothing.`
        );
        return {
          MINOR_GATE_REQUIRED: true,
          stoppedAt: memberId,
          reason: "minor account detected",
        };
      }
    }

    // ------------------------------------------------------------------
    // All members are adults — write presence for each.
    // Presence is BOOLEAN only: { resting: true, updatedAt: now }
    // NEVER write a count.
    // ------------------------------------------------------------------
    const nowMs = Date.now();
    const batch = db.batch();

    for (const memberId of memberIds) {
      // users/{memberId}/sabbath/presence — boolean presence signal
      const presenceRef = db
        .collection("users")
        .doc(memberId)
        .collection("sabbath")
        .doc("presence");

      batch.set(
        presenceRef,
        {
          resting: true,   // boolean signal — clients show text only, never numbers
          updatedAt: nowMs,
          // CRITICAL: Do NOT write a count of any kind here
        },
        { merge: true }
      );
    }

    // Write to shared graph: spaces/{spaceId}/sabbathPresence
    // "adultsResting: true" is a boolean signal — never a count.
    const groupId = spaceId || familyGroupId;
    if (groupId) {
      const spacePresenceRef = db.collection("spaces").doc(groupId);
      batch.set(
        spacePresenceRef,
        {
          sabbathPresence: {
            adultsResting: true, // boolean — clients MUST show text only, NEVER a number
            updatedAt: nowMs,
          },
        },
        { merge: true }
      );
    }

    await batch.commit();

    console.log(
      `[familySabbathSync] Synced presence for ${memberIds.length} adult(s) ` +
        `callerUid=${callerUid} groupId=${groupId || "none"}`
    );

    return {
      success: true,
      // Return the count of adults synced so the server can log it,
      // but clients MUST NOT display this number to users.
      memberCount: memberIds.length,
    };
  }
);

module.exports = { syncFamilySabbathPresence };
