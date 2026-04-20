// berean/controllers/getJourneySnapshot.ts
// Returns a user's discipleship journey snapshot: profile, open recommendations, follow-ups.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { discipleshipTrackerService } from "../services/DiscipleshipTrackerService";

export const bereanGetJourneySnapshot = onCall(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const userId = request.auth.uid;
    const snapshot = await discipleshipTrackerService.getJourneySnapshot(userId);

    return {
      success: true,
      profile: snapshot.profile,
      activeRecommendations: snapshot.recommendations,
      upcomingFollowUps: snapshot.followUps,
    };
  }
);
