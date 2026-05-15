// berean/controllers/getJourneySnapshot.ts
// Returns a user's discipleship journey snapshot: profile, open recommendations, follow-ups.
//
// FIX: The original import `{ discipleshipTrackerService }` referenced a named object
// export that does not exist — DiscipleshipTrackerService.ts only exports individual
// functions. Rewritten to use getRecentEvents() + direct Firestore reads.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { getRecentEvents } from "../services/DiscipleshipTrackerService";

export const bereanGetJourneySnapshot = onCall(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const userId = request.auth.uid;
    const db = admin.firestore();

    // 1. Load discipleship profile (may not exist for new users)
    const profileDoc = await db
      .collection("users")
      .doc(userId)
      .collection("discipleshipProfile")
      .doc(userId)
      .get()
      .catch(() => null);

    const profile = profileDoc?.exists
      ? profileDoc.data()
      : { totalStudySessions: 0, lastStudiedBook: null, updatedAt: null };

    // 2. Load recent events to derive focus areas
    const recentEvents = await getRecentEvents(userId, 20);

    // Tally books studied to surface top focus areas
    const bookCounts: Record<string, number> = {};
    for (const event of recentEvents) {
      if (event.passageReference) {
        const book = event.passageReference.split(" ")[0];
        bookCounts[book] = (bookCounts[book] ?? 0) + 1;
      }
    }
    const topFocusAreas = Object.entries(bookCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([book]) => book);

    // 3. Derive simple study recommendations from focus areas
    const activeRecommendations = topFocusAreas.map((book) => ({
      type: "continue_study",
      passageHint: book,
      reason: `You've been studying ${book} recently — keep going!`,
    }));

    // 4. Load upcoming follow-up prompts (pending, soonest first)
    const followUpSnap = await db
      .collection("users")
      .doc(userId)
      .collection("followUpPrompts")
      .where("status", "==", "pending")
      .orderBy("scheduledFor", "asc")
      .limit(5)
      .get()
      .catch(() => null);

    const upcomingFollowUps = followUpSnap?.docs.map((d) => d.data()) ?? [];

    return {
      success: true,
      profile: { ...profile, focusAreas: topFocusAreas },
      activeRecommendations,
      upcomingFollowUps,
    };
  }
);
