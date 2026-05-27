// integrations/gatherings/sendGatheringReminder.ts
// Send FCM push reminders to RSVP'd attendees

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { assertGatheringHost } from "../integrationCallableGuards";
import { writeAuditLog } from "../integrationAudit";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";

const db = admin.firestore();

export const gatheringsSendReminder = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringId = data["gatheringId"] as string | undefined;
  if (!gatheringId) return errorResponse("invalid-input");

  try {
    const gSnap = await assertGatheringHost(uid, gatheringId);
    const g = gSnap.data() as { title: string; startAt: admin.firestore.Timestamp };

    const rsvpSnap = await db.collection("gatherings").doc(gatheringId)
      .collection("rsvps").where("status", "in", ["going", "maybe"]).limit(500).get();

    const recipientUids = rsvpSnap.docs.map((d) => d.data()["uid"] as string).filter(Boolean);

    // Collect FCM tokens (max 2 per user to respect token limits)
    const tokens: string[] = [];
    for (const rUid of recipientUids) {
      const tSnap = await db.collection("users").doc(rUid).collection("fcmTokens").limit(2).get();
      tSnap.docs.forEach((d) => { const tok = d.data()["token"]; if (tok) tokens.push(tok as string); });
    }

    if (tokens.length > 0) {
      const hoursUntil = Math.round((g.startAt.toMillis() - Date.now()) / 3_600_000);
      const timeLabel = hoursUntil <= 1 ? "starting soon" : `in ${hoursUntil} hours`;
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title: `Reminder: ${g.title}`, body: `${g.title} is ${timeLabel}` },
        data: { type: "gathering_reminder", gatheringId },
      });
    }

    // Store reminder record
    const ref = db.collection("gatheringReminders").doc();
    await ref.set({
      reminderId: ref.id, gatheringId,
      scheduledFor: admin.firestore.FieldValue.serverTimestamp(),
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      recipientUids, status: "sent",
      createdByUid: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({ uid, action: "reminder_sent", metadata: { gatheringId } });
    return { success: true, recipientCount: recipientUids.length };
  } catch (e) {
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[gatheringsSendReminder]", e);
    return errorResponse("unknown");
  }
});
