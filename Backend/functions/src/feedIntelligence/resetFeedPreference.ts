import { onCall, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAuth, requireAppCheck } from "./moderation";
import type { FeedResetScope } from "./types";

export const resetFeedPreference = onCall(
  { enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
  async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);
    const scope = (request.data?.scope ?? "temporary") as FeedResetScope;

    const db = admin.firestore();
    const profileRef = db.doc(`users/${uid}/feedIntelligence/profile/main`);

    const update: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    switch (scope) {
      case "temporary":
        // Revoke session/now/today signals
        await revokeSignalsByDuration(uid, ["session", "now", "today"]);
        break;
      case "emotional":
        update["feedHealth.preferCalmContent"] = false;
        update["feedHealth.reduceRapidCuts"] = false;
        update["feedHealth.reduceOutrage"] = false;
        update["emotionalPreferences"] = {};
        await revokeSignalsByIntent(uid, ["emotionalRegulation"]);
        break;
      case "creator":
        update["creatorAffinities"] = {};
        break;
      case "topic":
        update["boostedTopics"] = {};
        update["suppressedTopics"] = {};
        break;
      case "all":
        update["activeModes"] = [];
        update["boostedTopics"] = {};
        update["suppressedTopics"] = {};
        update["creatorAffinities"] = {};
        update["emotionalPreferences"] = {};
        update["spiritualPreferences"] = {};
        update["feedHealth"] = {
          reduceOutrage: false,
          reduceRapidCuts: false,
          preferCalmContent: false,
          preserveDiversity: true,
        };
        await revokeAllActiveSignals(uid);
        break;
    }

    await profileRef.set(update, { merge: true });
    return { success: true, scope };
  }
);

async function revokeSignalsByDuration(uid: string, durations: string[]): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection(`users/${uid}/feedIntelligence/signals`)
    .where("status", "==", "active")
    .where("duration", "in", durations)
    .get();
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.update(doc.ref, { status: "revoked", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  if (!snap.empty) await batch.commit();
}

async function revokeSignalsByIntent(uid: string, intents: string[]): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection(`users/${uid}/feedIntelligence/signals`)
    .where("status", "==", "active")
    .where("intentType", "in", intents)
    .get();
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.update(doc.ref, { status: "revoked", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  if (!snap.empty) await batch.commit();
}

async function revokeAllActiveSignals(uid: string): Promise<void> {
  const db = admin.firestore();
  const snap = await db.collection(`users/${uid}/feedIntelligence/signals`)
    .where("status", "==", "active").get();
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.update(doc.ref, { status: "revoked", updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  if (!snap.empty) await batch.commit();
}
