// accessPassPermissions.ts — Admin and creator permission checks
//
// Verifies that the calling user is authorized to create/manage a pass
// for the specified target type and ID.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { AmenAccessTargetType } from "./accessPassTypes";

const db = admin.firestore();

/**
 * Verify that uid is an admin/owner/creator for the given target.
 * Throws HttpsError("permission-denied") if not authorized.
 */
export async function verifyAdminForTarget(
  uid: string,
  targetType: AmenAccessTargetType,
  targetId: string
): Promise<void> {
  switch (targetType) {
    case "church":
      await verifyChurchAdmin(uid, targetId);
      break;
    case "organization":
      await verifyOrgAdmin(uid, targetId);
      break;
    case "smallGroup":
      await verifyGroupAdmin(uid, targetId);
      break;
    case "space":
      await verifySpaceAdmin(uid, targetId);
      break;
    case "discussion":
      await verifyDiscussionAdmin(uid, targetId);
      break;
    case "event":
      await verifyEventAdmin(uid, targetId);
      break;
    case "sermonNotes":
      await verifySermonNotesAdmin(uid, targetId);
      break;
    case "prayerRoom":
      await verifyPrayerRoomAdmin(uid, targetId);
      break;
    default:
      throw new functions.https.HttpsError("permission-denied", "unknown-target-type");
  }
}

async function verifyChurchAdmin(uid: string, churchId: string): Promise<void> {
  const snap = await db.collection("churches").doc(churchId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "church-not-found");
  }
  const data = snap.data()!;
  const isOwner = data.ownerUserId === uid;
  const isAdmin = (data.adminUserIds as string[] ?? []).includes(uid);
  const isModerator = (data.moderatorUserIds as string[] ?? []).includes(uid);
  if (!isOwner && !isAdmin && !isModerator) {
    throw new functions.https.HttpsError("permission-denied", "not-church-admin");
  }
}

async function verifyOrgAdmin(uid: string, orgId: string): Promise<void> {
  const snap = await db.collection("organizations").doc(orgId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "org-not-found");
  }
  const data = snap.data()!;
  const isOwner = data.ownerUserId === uid;
  const isAdmin = (data.adminUserIds as string[] ?? []).includes(uid);
  if (!isOwner && !isAdmin) {
    throw new functions.https.HttpsError("permission-denied", "not-org-admin");
  }
}

async function verifyGroupAdmin(uid: string, groupId: string): Promise<void> {
  const memberRef = db.collection("groupLinks").doc(groupId).collection("members").doc(uid);
  const snap = await memberRef.get();
  if (!snap.exists || !snap.data()?.isAdmin) {
    throw new functions.https.HttpsError("permission-denied", "not-group-admin");
  }
}

async function verifySpaceAdmin(uid: string, spaceId: string): Promise<void> {
  const snap = await db.collection("spaces").doc(spaceId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "space-not-found");
  }
  const data = snap.data()!;
  if (data.createdByUid !== uid && !(data.adminUids as string[] ?? []).includes(uid)) {
    throw new functions.https.HttpsError("permission-denied", "not-space-admin");
  }
}

async function verifyDiscussionAdmin(uid: string, discussionId: string): Promise<void> {
  const snap = await db.collection("discussions").doc(discussionId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "discussion-not-found");
  }
  const data = snap.data()!;
  if (data.authorId !== uid) {
    throw new functions.https.HttpsError("permission-denied", "not-discussion-owner");
  }
}

async function verifyEventAdmin(uid: string, eventId: string): Promise<void> {
  const snap = await db.collection("events").doc(eventId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "event-not-found");
  }
  const data = snap.data()!;
  const isOrganizer = data.organizerUid === uid;
  const isAdmin = (data.adminUids as string[] ?? []).includes(uid);
  if (!isOrganizer && !isAdmin) {
    throw new functions.https.HttpsError("permission-denied", "not-event-admin");
  }
}

async function verifySermonNotesAdmin(uid: string, notesId: string): Promise<void> {
  const snap = await db.collection("sermonNotes").doc(notesId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "sermon-notes-not-found");
  }
  const data = snap.data()!;
  if (data.authorId !== uid && data.churchId) {
    // Also allow church admins to manage sermon note passes
    try {
      await verifyChurchAdmin(uid, data.churchId);
    } catch {
      throw new functions.https.HttpsError("permission-denied", "not-sermon-notes-admin");
    }
  } else if (data.authorId !== uid) {
    throw new functions.https.HttpsError("permission-denied", "not-sermon-notes-admin");
  }
}

async function verifyPrayerRoomAdmin(uid: string, roomId: string): Promise<void> {
  const snap = await db.collection("prayerRooms").doc(roomId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "prayer-room-not-found");
  }
  const data = snap.data()!;
  if (data.hostUid !== uid && !(data.adminUids as string[] ?? []).includes(uid)) {
    throw new functions.https.HttpsError("permission-denied", "not-prayer-room-admin");
  }
}

/** Verify uid is the creator/pass owner. */
export async function verifyPassAdmin(
  uid: string,
  accessPassId: string
): Promise<void> {
  const passSnap = await db.collection("accessPasses").doc(accessPassId).get();
  if (!passSnap.exists) {
    throw new functions.https.HttpsError("not-found", "pass-not-found");
  }
  const pass = passSnap.data()!;
  if (pass.createdByUid !== uid) {
    // Also check if they're admin for the target
    try {
      await verifyAdminForTarget(uid, pass.targetType, pass.targetId);
    } catch {
      throw new functions.https.HttpsError("permission-denied", "not-pass-admin");
    }
  }
}

/** Verify uid is admin for the target referenced by a request. */
export async function verifyRequestAdmin(uid: string, requestId: string): Promise<void> {
  const reqSnap = await db.collection("accessRequests").doc(requestId).get();
  if (!reqSnap.exists) {
    throw new functions.https.HttpsError("not-found", "request-not-found");
  }
  const req = reqSnap.data()!;
  await verifyAdminForTarget(uid, req.targetType, req.targetId);
}
