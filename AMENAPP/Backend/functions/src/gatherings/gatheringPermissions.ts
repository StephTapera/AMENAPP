// gatheringPermissions.ts
// Permission checks for Gathering callables.
// All checks are server-side — clients cannot bypass.

import * as admin from "firebase-admin";
import { AmenGathering } from "./gatheringTypes";

export class GatheringPermissionError extends Error {
  constructor(message: string, public readonly code: string = "permission-denied") {
    super(message);
    this.name = "GatheringPermissionError";
  }
}

const db = () => admin.firestore();

/**
 * Verify the caller can create a gathering under the given host.
 * For church/org/smallGroup hosts, the caller must be an admin of that entity.
 */
export async function assertCanCreateGathering(
  uid: string,
  hostType: string,
  hostId: string
): Promise<void> {
  if (hostType === "user") {
    if (hostId !== uid) {
      throw new GatheringPermissionError(
        "You can only create gatherings for yourself.",
        "permission-denied"
      );
    }
    return;
  }

  if (hostType === "church") {
    const adminDoc = await db()
      .collection("churches")
      .doc(hostId)
      .collection("admins")
      .doc(uid)
      .get();
    if (!adminDoc.exists) {
      throw new GatheringPermissionError(
        "You must be a church admin to create gatherings for this church.",
        "permission-denied"
      );
    }
    return;
  }

  if (hostType === "organization") {
    const adminDoc = await db()
      .collection("organizations")
      .doc(hostId)
      .collection("admins")
      .doc(uid)
      .get();
    if (!adminDoc.exists) {
      throw new GatheringPermissionError(
        "You must be an org admin to create gatherings for this organization.",
        "permission-denied"
      );
    }
    return;
  }

  if (hostType === "smallGroup") {
    const memberDoc = await db()
      .collection("smallGroups")
      .doc(hostId)
      .collection("members")
      .doc(uid)
      .get();
    const role = memberDoc.data()?.["role"] as string | undefined;
    if (!memberDoc.exists || !["leader", "admin"].includes(role ?? "")) {
      throw new GatheringPermissionError(
        "You must be a group leader to create gatherings for this small group.",
        "permission-denied"
      );
    }
    return;
  }

  throw new GatheringPermissionError("Unknown host type.", "invalid-host-type");
}

/**
 * Verify the caller is the host or an admin of the gathering.
 */
export async function assertIsGatheringHost(
  uid: string,
  gathering: AmenGathering
): Promise<void> {
  if (gathering.createdByUid === uid) return;

  // Check if uid is an admin for the host entity
  try {
    await assertCanCreateGathering(uid, gathering.hostType, gathering.hostId);
  } catch {
    throw new GatheringPermissionError(
      "You must be the gathering host to perform this action.",
      "permission-denied"
    );
  }
}

/**
 * Fetch a gathering and assert the caller is the host/admin.
 */
export async function fetchGatheringAsHost(
  uid: string,
  gatheringId: string
): Promise<admin.firestore.DocumentSnapshot<admin.firestore.DocumentData>> {
  const snap = await db().collection("gatherings").doc(gatheringId).get();
  if (!snap.exists) {
    throw new GatheringPermissionError("Gathering not found.", "not-found");
  }
  const gathering = snap.data() as AmenGathering;
  await assertIsGatheringHost(uid, gathering);
  return snap;
}
