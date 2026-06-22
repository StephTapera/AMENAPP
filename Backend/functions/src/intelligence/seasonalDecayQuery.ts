// seasonalDecayQuery.ts — Backend/functions/src/intelligence
// Callable: getDecayedSignalWeights
// Returns the exponential-decay weights of a user's recent signals, grouped by type.
// Used by SeasonsInsightService when client-side ring buffer is insufficient
// (e.g., first app launch, cross-device continuity).
//
// Invariants:
//  • Decay formula: weight = 0.5^(daysSinceSignal / halfLifeDays); same as client DecayEngine
//  • tierCeiling "s" signals are NEVER included
//  • Only returns aggregate weights per type — individual signal content is not returned
//  • Deployed to us-east1

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface DecayedTypeWeight {
  signalType: string;
  totalWeight: number;
  count: number;
}

export const getDecayedSignalWeights = functions.onCall({ enforceAppCheck: true, region: "us-east1" }, async (request): Promise<{ weights: DecayedTypeWeight[]; dominantType: string | null }> => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Auth required");
    }

    const uid = request.auth.uid;
    const requestedUID = request.data?.uid as string | undefined;

    if (requestedUID && requestedUID !== uid) {
      throw new functions.HttpsError("permission-denied", "Cannot query another user's signals");
    }

    const db = admin.firestore();
    const nowMs = Date.now();
    const ninetyDaysAgo = admin.firestore.Timestamp.fromMillis(nowMs - 90 * 86_400_000);

    const snap = await db
      .collection("contextSignals")
      .doc(uid)
      .collection("signals")
      .where("tierCeiling", "!=", "s")
      .where("occurredAt", ">=", ninetyDaysAgo)
      .orderBy("tierCeiling")                      // required for != compound query
      .orderBy("occurredAt", "desc")
      .limit(200)
      .get();

    const weightsByType: Record<string, { totalWeight: number; count: number }> = {};

    for (const doc of snap.docs) {
      const d = doc.data();
      const type: string = d.type ?? "unknown";
      const halfLifeDays: number = d.decayHalfLifeDays ?? 14;
      const occurredAt: FirebaseFirestore.Timestamp = d.occurredAt;
      const daysSince = (nowMs - occurredAt.toMillis()) / 86_400_000;
      const weight = Math.pow(0.5, daysSince / Math.max(halfLifeDays, 0.1));

      if (!weightsByType[type]) {
        weightsByType[type] = { totalWeight: 0, count: 0 };
      }
      weightsByType[type].totalWeight += weight;
      weightsByType[type].count += 1;
    }

    const weights: DecayedTypeWeight[] = Object.entries(weightsByType)
      .map(([signalType, { totalWeight, count }]) => ({
        signalType,
        totalWeight: Math.round(totalWeight * 1000) / 1000,   // 3 decimal places
        count,
      }))
      .sort((a, b) => b.totalWeight - a.totalWeight);

    const dominantType = weights.length > 0 ? weights[0].signalType : null;

    return { weights, dominantType };
  }
);
