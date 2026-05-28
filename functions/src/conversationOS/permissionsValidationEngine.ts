// permissionsValidationEngine.ts
// AMEN Conversation OS — Server-Side Permissions Validation
//
// AI must NEVER bypass permissions.
// Every AI operation validates access before any data is retrieved.
// Fails closed — deny on any uncertainty.

import * as admin from "firebase-admin";
import { ConversationOSSurface, PermissionsContext, isSensitiveSurface } from "./types";

const db = admin.firestore();

// MARK: - Primary Permission Gate

export async function validatePermissions(ctx: PermissionsContext): Promise<{
  allowed: boolean;
  reason?: string;
}> {
  // 1. User must be authenticated (caller validated by Firebase Functions auth)
  if (!ctx.userId) {
    return { allowed: false, reason: "unauthenticated" };
  }

  // 2. Sensitive surfaces require explicit room-level opt-in
  if (isSensitiveSurface(ctx.surface)) {
    const optInAllowed = await checkSensitiveSpaceOptIn(ctx);
    if (!optInAllowed) {
      return {
        allowed: false,
        reason: `AI is not enabled in this ${ctx.surface.replace("_", " ")}. An admin must enable it.`,
      };
    }
  }

  // 3. Space membership check
  if (ctx.spaceId) {
    const isMember = await checkSpaceMembership(ctx.userId, ctx.spaceId);
    if (!isMember) {
      return { allowed: false, reason: "not_a_member" };
    }
  }

  // 4. Org membership check
  if (ctx.orgId) {
    const isOrgMember = await checkOrgMembership(ctx.userId, ctx.orgId);
    if (!isOrgMember) {
      return { allowed: false, reason: "not_in_organization" };
    }
  }

  // 5. Room-level restrictions
  if (ctx.roomId) {
    const roomAccess = await checkRoomAccess(ctx.userId, ctx.roomId, ctx.surface);
    if (!roomAccess.allowed) {
      return { allowed: false, reason: roomAccess.reason };
    }
  }

  return { allowed: true };
}

// MARK: - Space Membership

async function checkSpaceMembership(userId: string, spaceId: string): Promise<boolean> {
  try {
    // Check subcollection members/{uid}
    const memberDoc = await db
      .collection("spaces").doc(spaceId)
      .collection("members").doc(userId)
      .get();
    if (memberDoc.exists) return true;

    // Check memberIds array on the space document
    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) return false;
    const memberIds = spaceDoc.data()?.memberIds ?? [];
    return Array.isArray(memberIds) && memberIds.includes(userId);
  } catch {
    return false; // Fail closed
  }
}

// MARK: - Org Membership

async function checkOrgMembership(userId: string, orgId: string): Promise<boolean> {
  try {
    const memberDoc = await db
      .collection("organizations").doc(orgId)
      .collection("members").doc(userId)
      .get();
    return memberDoc.exists;
  } catch {
    return false;
  }
}

// MARK: - Room Access

async function checkRoomAccess(
  userId: string,
  roomId: string,
  surface: ConversationOSSurface
): Promise<{ allowed: boolean; reason?: string }> {
  // Leadership rooms: only leadership-role members
  if (surface === "leadership_room") {
    const allowed = await checkLeadershipRole(userId, roomId);
    return allowed
      ? { allowed: true }
      : { allowed: false, reason: "leadership_role_required" };
  }

  // Admin channels: only admins
  if (surface === "admin_channel") {
    const allowed = await checkAdminRole(userId);
    return allowed
      ? { allowed: true }
      : { allowed: false, reason: "admin_role_required" };
  }

  // Prayer rooms: require room opt-in by the room owner
  if (surface === "prayer_room") {
    const optIn = await checkPrayerRoomOptIn(roomId);
    return optIn
      ? { allowed: true }
      : { allowed: false, reason: "prayer_room_ai_not_enabled" };
  }

  return { allowed: true };
}

// MARK: - Role Checks

async function checkLeadershipRole(userId: string, roomId: string): Promise<boolean> {
  try {
    const doc = await db.collection("rooms").doc(roomId).collection("members").doc(userId).get();
    if (!doc.exists) return false;
    const role = doc.data()?.role ?? "";
    return ["leader", "admin", "pastor", "moderator"].includes(role);
  } catch {
    return false;
  }
}

async function checkAdminRole(userId: string): Promise<boolean> {
  try {
    const userRecord = await admin.auth().getUser(userId);
    return userRecord.customClaims?.admin === true;
  } catch {
    return false;
  }
}

async function checkPrayerRoomOptIn(roomId: string): Promise<boolean> {
  try {
    const doc = await db.collection("rooms").doc(roomId).get();
    return doc.data()?.aiSummaryOptIn === true;
  } catch {
    return false;
  }
}

// MARK: - Sensitive Space Opt-In

async function checkSensitiveSpaceOptIn(ctx: PermissionsContext): Promise<boolean> {
  const id = ctx.spaceId ?? ctx.roomId;
  if (!id) return false;
  try {
    const collection = ctx.spaceId ? "spaces" : "rooms";
    const doc = await db.collection(collection).doc(id).get();
    return doc.data()?.conversationOSOptIn === true;
  } catch {
    return false;
  }
}

// MARK: - Summary Access (reading existing summaries)

export async function validateSummaryReadAccess(
  userId: string,
  spaceId: string,
  summaryId: string
): Promise<boolean> {
  try {
    const summaryDoc = await db
      .collection("spaces").doc(spaceId)
      .collection("summaries").doc(summaryId)
      .get();
    if (!summaryDoc.exists) return false;

    // User must be a member of the space the summary belongs to
    return await checkSpaceMembership(userId, spaceId);
  } catch {
    return false;
  }
}

// MARK: - Personalized Summary Access

export async function validatePersonalizedSummaryAccess(
  userId: string,
  targetUserId: string
): Promise<boolean> {
  // Users can only access their own personalized summaries
  return userId === targetUserId;
}
