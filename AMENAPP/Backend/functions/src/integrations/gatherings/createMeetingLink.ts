// integrations/gatherings/createMeetingLink.ts
// Creates a provider meeting link for a gathering. Idempotent per gathering+provider.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { assertGatheringHost, assertProviderConnected, fetchTokenRecord, assertFeatureEnabled } from "../integrationCallableGuards";
import { checkIdempotency, recordIdempotency } from "../integrationIdempotency";
import { writeAuditLog } from "../integrationAudit";
import { checkRateLimit } from "../integrationRateLimits";
import { decryptToken, refreshProviderToken } from "../oauth/oauthRefresh";
import { MicrosoftGraphProvider } from "../providers/MicrosoftGraphProvider";
import { ZoomMeetingProvider } from "../providers/ZoomProvider";
import { AmenIntegrationError, AmenProviderError, errorResponse } from "../integrationErrors";
import type { AmenIntegrationProvider } from "../types";

const db = admin.firestore();

export const gatheringsCreateMeetingLink = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringId = data["gatheringId"] as string | undefined;
  const provider = data["provider"] as AmenIntegrationProvider | undefined;

  if (!gatheringId || !provider || !["microsoft", "zoom"].includes(provider)) {
    return errorResponse("invalid-input");
  }

  const idempotencyKey = `meetinglink_${gatheringId}_${provider}`;

  try {
    await assertFeatureEnabled("amen_integrations_enabled");
    await assertFeatureEnabled("amen_gathering_meeting_links_enabled");

    const { isDuplicate, existingResult } = await checkIdempotency(idempotencyKey);
    if (isDuplicate && existingResult) return existingResult;

    await checkRateLimit(uid, "meeting_create", provider);

    const [gatheringSnap] = await Promise.all([
      assertGatheringHost(uid, gatheringId),
      assertProviderConnected(uid, provider),
    ]);

    const g = gatheringSnap.data() as { title: string; startAt: admin.firestore.Timestamp; endAt?: admin.firestore.Timestamp; timezone?: string };

    const accountId = `${uid}_${provider}`;
    const tokenRecord = await fetchTokenRecord(accountId);
    let accessToken: string;
    try {
      accessToken = decryptToken(tokenRecord.encryptedAccessToken);
      if (tokenRecord.expiresAt.toMillis() <= Date.now() + 60_000) {
        accessToken = await refreshProviderToken(uid, provider);
      }
    } catch {
      accessToken = await refreshProviderToken(uid, provider);
    }

    const providerImpl = provider === "microsoft" ? new MicrosoftGraphProvider() : new ZoomMeetingProvider();
    const meeting = await providerImpl.createMeeting(accessToken, {
      gatheringId,
      title: g.title,
      startAtMs: g.startAt.toMillis(),
      endAtMs: g.endAt?.toMillis(),
      timezone: g.timezone ?? "UTC",
      waitingRoom: true,
    });

    const now = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();
    // Main doc — joinUrl safe for all participants
    batch.set(db.collection("gatheringMeetingLinks").doc(gatheringId), {
      gatheringId, provider,
      providerMeetingId: meeting.providerMeetingId,
      joinUrl: meeting.joinUrl,
      startAt: g.startAt,
      ...(g.endAt && { endAt: g.endAt }),
      createdByUid: uid,
      idempotencyKey,
      status: "active",
      createdAt: now,
      updatedAt: now,
    });

    // Host URL stored in separate subcollection — NEVER returned to participants
    if (meeting.hostUrl) {
      batch.set(
        db.collection("gatheringMeetingLinks").doc(gatheringId).collection("hostSecrets").doc("hostUrl"),
        { hostUrl: meeting.hostUrl, createdAt: now }
      );
    }

    // Update gathering location to reflect online link
    batch.update(db.collection("gatherings").doc(gatheringId), {
      "location.onlineUrl": meeting.joinUrl,
      "location.type": "online",
      "audit.updatedAt": now,
    });

    await batch.commit();

    const result = {
      success: true, gatheringId, provider,
      joinUrl: meeting.joinUrl,
      providerMeetingId: meeting.providerMeetingId,
    };

    await Promise.all([
      recordIdempotency(idempotencyKey, result),
      writeAuditLog({ uid, action: "meeting_link_created", provider, metadata: { gatheringId } }),
    ]);

    return result;
  } catch (e) {
    writeAuditLog({ uid, action: "meeting_link_failed", provider, metadata: { gatheringId: gatheringId ?? "" } }).catch(() => {});
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    if (e instanceof AmenProviderError) return errorResponse(e.code);
    console.error("[gatheringsCreateMeetingLink]", e);
    return errorResponse("unknown");
  }
});
