import * as admin from "firebase-admin";
import type { FeedIntelligenceProfile, ClassificationResult, FeedDirectionDuration, FeedDirectionIntensity } from "./types";
import { computeIntensityWeight, clamp, MAX_BOOST, MAX_SUPPRESS } from "./classifyFeedDirection";

export async function applyFeedPreferenceWeights(
  uid: string,
  classification: ClassificationResult,
  duration: FeedDirectionDuration,
  intensity: FeedDirectionIntensity,
  affectedSurfaces: string[]
): Promise<void> {
  const db = admin.firestore();
  const profileRef = db.doc(`users/${uid}/feedIntelligence/profile/main`);
  const weight = computeIntensityWeight(intensity);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(profileRef);
    const existing = (snap.exists ? snap.data() : null) as FeedIntelligenceProfile | null;

    const profile: FeedIntelligenceProfile = existing ?? {
      uid,
      version: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      activeModes: [],
      boostedTopics: {},
      suppressedTopics: {},
      creatorAffinities: {},
      emotionalPreferences: {},
      spiritualPreferences: {},
      surfaceWeights: {},
      feedHealth: {
        reduceOutrage: false,
        reduceRapidCuts: false,
        preferCalmContent: false,
        preserveDiversity: true,
      },
      resetAvailable: true,
    };

    // Apply topic boosts
    for (const topic of classification.topicsIncreased) {
      const current = profile.boostedTopics[topic] ?? 0;
      profile.boostedTopics[topic] = clamp(current + weight, 0, MAX_BOOST);
    }

    // Apply topic suppressions
    for (const topic of classification.topicsDecreased) {
      const current = profile.suppressedTopics[topic] ?? 0;
      profile.suppressedTopics[topic] = clamp(current + weight, 0, Math.abs(MAX_SUPPRESS));
    }

    // Apply feed health
    if (classification.feedHealthUpdates.reduceOutrage) {
      profile.feedHealth.reduceOutrage = true;
    }
    if (classification.feedHealthUpdates.reduceRapidCuts) {
      profile.feedHealth.reduceRapidCuts = true;
    }
    if (classification.feedHealthUpdates.preferCalmContent) {
      profile.feedHealth.preferCalmContent = true;
    }
    if (classification.feedHealthUpdates.preserveDiversity !== undefined) {
      profile.feedHealth.preserveDiversity = true; // Never allow false from client
    }

    // Apply modes
    for (const mode of classification.modesActivated) {
      if (!profile.activeModes.includes(mode)) {
        profile.activeModes.push(mode);
      }
    }

    profile.version = (profile.version ?? 0) + 1;
    profile.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    profile.resetAvailable = true;

    tx.set(profileRef, profile, { merge: false });
  });
}
