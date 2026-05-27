// remoteConfigSync.ts
// Syncs Firebase Remote Config values to Firestore remoteConfigCache collection.
// assertFeatureEnabled() reads from this cache — without it, all server-side feature
// gates fail open. Runs every 5 minutes.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

// Feature flags to sync. Mirrors AMENFeatureFlags System 39 + key kill switches.
const FLAGS_TO_SYNC: string[] = [
  // System 39: Integrations Platform
  "amen_integrations_enabled",
  "amen_microsoft_enabled",
  "amen_zoom_enabled",
  "amen_slack_enabled",
  "amen_gatherings_enabled",
  "amen_gathering_meeting_links_enabled",
  "amen_gathering_reminders_enabled",
  "amen_gathering_follow_ups_enabled",
  "amen_gathering_ai_suggestions_enabled",
  "amen_integration_admin_workflows_enabled",
  "amen_integration_audit_logging_enabled",
  "amen_integrations_kill_switch",
  // Other kill switches watched by callables
  "berean_ai_enabled",
  "church_notes_enabled",
  "access_pass_enabled",
];

export const syncRemoteConfigToFirestore = functions
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .pubsub.schedule("every 5 minutes")
  .onRun(async () => {
    try {
      const rc = admin.remoteConfig();
      const template = await rc.getTemplate();
      const parameters = template.parameters ?? {};

      const batch = db.batch();
      let updateCount = 0;

      for (const flagName of FLAGS_TO_SYNC) {
        const param = parameters[flagName];
        if (!param) continue;

        // Resolve the default value (used when no condition matches)
        const defaultValueEntry = param.defaultValue;
        let value: boolean | null = null;

        if (
          defaultValueEntry &&
          "value" in defaultValueEntry &&
          typeof defaultValueEntry.value === "string"
        ) {
          const raw = defaultValueEntry.value.toLowerCase().trim();
          if (raw === "true") value = true;
          else if (raw === "false") value = false;
        }

        if (value === null) continue; // Skip params with no boolean default

        const ref = db.collection("remoteConfigCache").doc(flagName);
        batch.set(ref, {
          value,
          syncedAt: admin.firestore.FieldValue.serverTimestamp(),
          parameterGroup: param.parameterGroups?.[0] ?? null,
        }, { merge: false });

        updateCount++;
      }

      await batch.commit();
      console.log(`[remoteConfigSync] Synced ${updateCount} flags to Firestore`);
    } catch (e) {
      // Log but never throw — a sync failure must never affect user-facing calls.
      // assertFeatureEnabled() fails open on missing cache docs, so the app stays available.
      console.error("[remoteConfigSync] Sync failed — feature gates will remain open:", e);
    }
  });

// One-shot callable for manual sync (admin use only — not client-accessible via App Check)
export const manualSyncRemoteConfig = functions.https.onCall(async (_data, context) => {
  if (!context.auth?.token?.admin) {
    return { error: "admin-only" };
  }
  try {
    const rc = admin.remoteConfig();
    const template = await rc.getTemplate();
    const parameters = template.parameters ?? {};
    const batch = db.batch();
    let count = 0;
    for (const flagName of FLAGS_TO_SYNC) {
      const param = parameters[flagName];
      if (!param) continue;
      const defaultValueEntry = param.defaultValue;
      let value: boolean | null = null;
      if (defaultValueEntry && "value" in defaultValueEntry && typeof defaultValueEntry.value === "string") {
        const raw = defaultValueEntry.value.toLowerCase().trim();
        if (raw === "true") value = true;
        else if (raw === "false") value = false;
      }
      if (value === null) continue;
      batch.set(db.collection("remoteConfigCache").doc(flagName), {
        value,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: false });
      count++;
    }
    await batch.commit();
    return { synced: count };
  } catch (e) {
    console.error("[manualSyncRemoteConfig]", e);
    return { error: "sync-failed" };
  }
});
