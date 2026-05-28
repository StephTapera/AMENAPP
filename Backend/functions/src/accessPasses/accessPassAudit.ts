// accessPassAudit.ts — Audit event logging for Access Passes
//
// Privacy-safe: never logs prayer content, message bodies, note text, tokens, or tokenHash.
// Logs only broad reason codes, target type, platform, and pass IDs.

import * as admin from "firebase-admin";
import { AccessPassEvent } from "./accessPassTypes";

const db = admin.firestore();

export async function logAccessPassEvent(
  event: Omit<AccessPassEvent, "eventId" | "createdAt">
): Promise<void> {
  const eventId = db
    .collection("accessPasses")
    .doc(event.accessPassId)
    .collection("events")
    .doc().id;

  const record: AccessPassEvent = {
    ...event,
    eventId,
    createdAt: admin.firestore.Timestamp.now(),
  };

  await db
    .collection("accessPasses")
    .doc(event.accessPassId)
    .collection("events")
    .doc(eventId)
    .set(record);
}

export async function logResolved(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid?: string,
  anonymousSessionId?: string,
  devicePlatform?: string,
  appVersion?: string
): Promise<void> {
  await logAccessPassEvent({
    type: "resolved",
    accessPassId,
    targetType,
    targetId,
    uid,
    anonymousSessionId,
    devicePlatform: devicePlatform as any,
    appVersion,
  });
}

export async function logJoined(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid: string
): Promise<void> {
  await logAccessPassEvent({ type: "joined", accessPassId, targetType, targetId, uid });
}

export async function logRequested(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid: string
): Promise<void> {
  await logAccessPassEvent({ type: "requested", accessPassId, targetType, targetId, uid });
}

export async function logCheckedIn(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid: string
): Promise<void> {
  await logAccessPassEvent({ type: "checkedIn", accessPassId, targetType, targetId, uid });
}

export async function logPreviewed(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid?: string
): Promise<void> {
  await logAccessPassEvent({ type: "previewed", accessPassId, targetType, targetId, uid });
}

export async function logDenied(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid?: string,
  reason?: string
): Promise<void> {
  await logAccessPassEvent({ type: "denied", accessPassId, targetType, targetId, uid, reason });
}

export async function logRevoked(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid: string,
  reason?: string
): Promise<void> {
  await logAccessPassEvent({ type: "revoked", accessPassId, targetType, targetId, uid, reason });
}

export async function logRateLimited(
  accessPassId: string,
  targetType: string,
  targetId: string,
  uid?: string
): Promise<void> {
  await logAccessPassEvent({ type: "rateLimited", accessPassId, targetType, targetId, uid });
}
