// integrations/index.ts
// AMEN Integrations Platform — all callable exports
// App Check enforced globally via Firebase project config

// OAuth lifecycle
export { integrationsStartOAuth } from "./oauth/oauthStart";
export { integrationsCompleteOAuth } from "./oauth/oauthCallback";
export { integrationsRefreshConnection } from "./oauth/oauthRefresh";
export { integrationsDisconnectProvider } from "./oauth/oauthRevoke";

// Gatherings integration
export { gatheringsCreateMeetingLink } from "./gatherings/createMeetingLink";
export { gatheringsSendReminder } from "./gatherings/sendGatheringReminder";
export { gatheringsCompleteFollowUp } from "./gatherings/completeGatheringFollowUp";

// AI suggestions (Berean orchestration layer)
export { gatheringSuggestTitles } from "./intelligence/gatheringTitleSuggestions";
export { gatheringSuggestAgenda } from "./intelligence/gatheringAgendaSuggestions";
export { gatheringSuggestScripture } from "./intelligence/gatheringScriptureFocus";
export { gatheringSuggestFollowUps } from "./intelligence/gatheringFollowUps";
export { gatheringGenerateRecap } from "./intelligence/gatheringRecapFromVerifiedContent";

// List connections
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

export const integrationsListConnections = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  try {
    const snap = await db.collection("integrationAccounts").where("uid", "==", uid).get();
    const connections = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        accountId: d["accountId"],
        provider: d["provider"],
        status: d["status"],
        isOrgLevel: d["isOrgLevel"] ?? false,
        displayName: d["providerMetadata"]?.["displayName"],
        email: d["providerMetadata"]?.["email"],
        workspaceName: d["providerMetadata"]?.["workspaceName"],
        connectedAt: (d["connectedAt"] as admin.firestore.Timestamp)?.toMillis(),
        expiresAt: (d["expiresAt"] as admin.firestore.Timestamp | undefined)?.toMillis(),
      };
    });
    return { connections };
  } catch (e) {
    console.error("[integrationsListConnections]", e);
    return { connections: [] };
  }
});

// List available Slack channels for a connected workspace
export const integrationsListSlackChannels = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  const { assertProviderConnected, fetchTokenRecord } = await import("./integrationCallableGuards");
  const { decryptToken } = await import("./oauth/oauthRefresh");
  const { SlackProviderImpl } = await import("./providers/SlackProvider");

  try {
    await assertProviderConnected(uid, "slack");
    const tokenRecord = await fetchTokenRecord(`${uid}_slack`);
    const accessToken = decryptToken(tokenRecord.encryptedAccessToken);
    const channels = await new SlackProviderImpl().listChannels(accessToken);
    return { channels };
  } catch (e) {
    console.error("[integrationsListSlackChannels]", e);
    return { channels: [] };
  }
});

// Send a Slack notification for a gathering event
export const integrationsSendSlackGatheringNotification = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return { errorCode: "auth-required" };

  const channelId = data["channelId"] as string | undefined;
  const gatheringId = data["gatheringId"] as string | undefined;
  if (!channelId || !gatheringId) return { errorCode: "invalid-input" };

  const { assertProviderConnected, fetchTokenRecord, assertGatheringHost } = await import("./integrationCallableGuards");
  const { decryptToken } = await import("./oauth/oauthRefresh");
  const { SlackProviderImpl } = await import("./providers/SlackProvider");
  const { writeAuditLog } = await import("./integrationAudit");

  try {
    const [gSnap] = await Promise.all([
      assertGatheringHost(uid, gatheringId),
      assertProviderConnected(uid, "slack"),
    ]);

    const g = gSnap.data() as { title: string; startAt: admin.firestore.Timestamp };
    const tokenRecord = await fetchTokenRecord(`${uid}_slack`);
    const accessToken = decryptToken(tokenRecord.encryptedAccessToken);

    // Safe metadata only — no prayer content, no private data
    const startDate = g.startAt.toDate().toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" });
    const text = `📅 New gathering: *${g.title}* — ${startDate}\nView in AMEN: https://amen.app/gathering/${gatheringId}`;

    await new SlackProviderImpl().sendChannelNotification(accessToken, { channelId, text });
    await writeAuditLog({ uid, action: "slack_notification_sent", provider: "slack", metadata: { gatheringId } });

    return { success: true };
  } catch (e) {
    console.error("[integrationsSendSlackGatheringNotification]", e);
    return { errorCode: "unknown" };
  }
});
