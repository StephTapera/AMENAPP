import { onCall, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAuth, requireAppCheck } from "./moderation";
import type { FeedIntelligenceProfile } from "./types";

export const getFeedIntelligenceSummary = onCall(
  { enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
  async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);
    const db = admin.firestore();

    const now = admin.firestore.Timestamp.now();
    const [profileSnap, signalsSnap] = await Promise.all([
      db.doc(`users/${uid}/feedIntelligence/profile/main`).get(),
      db.collection(`users/${uid}/feedIntelligence/signals`)
        .where("status", "==", "active")
        .orderBy("createdAt", "desc")
        .limit(20)
        .get(),
    ]);

    const profile = (profileSnap.exists ? profileSnap.data() : null) as FeedIntelligenceProfile | null;
    const activeSignals = signalsSnap.docs
      .filter((d) => {
        const exp = d.data().expiresAt;
        return !exp || exp.toMillis() > now.toMillis();
      })
      .map((d) => {
        const data = d.data();
        return {
          id: d.id,
          interpretedSummary: data.interpretedSummary ?? "",
          intentType: data.intentType ?? "unknown",
          duration: data.duration ?? "today",
          intensity: data.intensity ?? "medium",
          affectedSurfaces: data.affectedSurfaces ?? [],
          status: data.status ?? "active",
          createdAt: data.createdAt?.toDate()?.toISOString() ?? null,
          expiresAt: data.expiresAt?.toDate()?.toISOString() ?? null,
        };
      });

    return {
      activeSignals,
      activeModes: profile?.activeModes ?? [],
      boostedTopics: profile?.boostedTopics ?? {},
      suppressedTopics: profile?.suppressedTopics ?? {},
      feedHealth: profile?.feedHealth ?? {
        reduceOutrage: false,
        reduceRapidCuts: false,
        preferCalmContent: false,
        preserveDiversity: true,
      },
    };
  }
);
