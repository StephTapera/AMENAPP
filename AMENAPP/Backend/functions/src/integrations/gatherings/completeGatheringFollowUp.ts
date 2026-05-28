// integrations/gatherings/completeGatheringFollowUp.ts
// Host completes post-gathering follow-up — user must confirm AI suggestions before storage

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { assertGatheringHost } from "../integrationCallableGuards";
import { writeAuditLog } from "../integrationAudit";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";

const db = admin.firestore();

export const gatheringsCompleteFollowUp = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringId = data["gatheringId"] as string | undefined;
  if (!gatheringId) return errorResponse("invalid-input");

  // If content is AI-generated, user must explicitly confirm it before storage
  if (data["isAIGenerated"] === true && data["userConfirmed"] !== true) {
    return errorResponse("invalid-input");
  }

  const scripture = data["scripture"] as string | undefined;
  const actionItems = data["actionItems"] as string[] | undefined;
  const prayerPoints = data["prayerPoints"] as string[] | undefined;
  const shareToSpaceId = data["shareToSpaceId"] as string | undefined;

  try {
    await assertGatheringHost(uid, gatheringId);

    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("gatheringFollowUps").doc(gatheringId).set({
      gatheringId, status: "completed", hostUid: uid,
      ...(scripture ? { scripture } : {}),
      ...(actionItems ? { actionItems } : {}),
      ...(prayerPoints ? { prayerPoints } : {}),
      ...(shareToSpaceId ? { sharedToSpaceId: shareToSpaceId } : {}),
      completedAt: now, createdAt: now, updatedAt: now,
    }, { merge: true });

    await db.collection("gatherings").doc(gatheringId).update({
      status: "completed",
      "audit.updatedAt": now,
    });

    await writeAuditLog({ uid, action: "follow_up_completed", metadata: { gatheringId } });
    return { success: true, gatheringId };
  } catch (e) {
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[gatheringsCompleteFollowUp]", e);
    return errorResponse("unknown");
  }
});
