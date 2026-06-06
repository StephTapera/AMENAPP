/**
 * eventMatcher.ts
 *
 * Living Intelligence — Event Matching
 * Matches upcoming church/community events to a user based on:
 *   - Church involvement (+30)
 *   - Coarse geo proximity (+25)
 *   - Friends attending (+20) — reason string only, never a count
 *   - Age group fit (+15)
 *   - Liturgical relevance (+10)
 *
 * Privacy rules:
 *   - Coarse geo only (lat/lng rounded to ~50km grid before reaching this CF)
 *   - "Friends attending" shows reason string, never a count
 *   - No spectacle counters of any kind
 *
 * Auth required. Rate-limited.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import type {
  IntelligenceCard,
  CardAction,
  BackingEntity,
} from "./contracts";

const db = admin.firestore();

// Approximate degrees-per-50km for coarse proximity check
const COARSE_PROXIMITY_DEGREES = 0.45;

interface MatchEventsRequest {
  uid: string;
  coarseGeo?: { lat: number; lng: number };
  followedChurchIds: string[];
  maxResults?: number;
}

interface EventDoc {
  id: string;
  title: string;
  churchId: string;
  churchName?: string;
  description?: string;
  ageGroup?: string; // e.g. "YOUTH", "ADULT", "SENIOR", "ALL"
  liturgicalTopics?: string[];
  location?: { lat: number; lng: number };
  startTime: admin.firestore.Timestamp;
  expiresAt?: admin.firestore.Timestamp;
  fromVerifiedChurch?: boolean;
}

// Approximate liturgical season from date
function getLiturgicalSeason(date: Date): string {
  const month = date.getMonth() + 1;
  const day = date.getDate();

  // Very coarse liturgical season classification
  if (month === 12 && day >= 1) return "ADVENT";
  if (month === 12 && day >= 25) return "CHRISTMAS";
  if (month === 1) return "CHRISTMAS";
  if (month === 2 || (month === 3 && day < 15)) return "LENT_PRE";
  if (month === 3 || (month === 4 && day < 15)) return "LENT";
  if (month === 4 && day >= 15) return "EASTER";
  if (month === 5) return "EASTER";
  return "ORDINARY_TIME";
}

function topicsMatchSeason(topics: string[], season: string): boolean {
  const topicStr = topics.join(" ").toUpperCase();
  return topicStr.includes(season) || topicStr.includes("ORDINARY") && season === "ORDINARY_TIME";
}

function ageTierFromClaim(ageTier?: string): string {
  // Maps user's Firebase custom claim ageTier to event ageGroup vocabulary
  if (!ageTier) return "ALL";
  const t = ageTier.toUpperCase();
  if (t.includes("YOUTH") || t.includes("TEEN")) return "YOUTH";
  if (t.includes("SENIOR") || t.includes("ELDER")) return "SENIOR";
  return "ADULT";
}

export const matchEventsForUser = onCall(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    enforceAppCheck: false, // App Check handled by caller context
  },
  async (request) => {
    // 1. Auth check
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;

    // 2. Rate limit
    await enforceRateLimit(uid, [
      RATE_LIMITS.SUGGEST_PER_MINUTE,
      RATE_LIMITS.SUGGEST_PER_DAY,
    ]);

    const data = request.data as MatchEventsRequest;
    const { coarseGeo, followedChurchIds = [], maxResults = 10 } = data;

    const now = Date.now();
    const nowTs = admin.firestore.Timestamp.fromMillis(now);

    // 3. Fetch upcoming events (not yet expired)
    let eventsQuery: admin.firestore.Query = db.collection("events")
      .where("startTime", ">", nowTs)
      .orderBy("startTime", "asc")
      .limit(100);

    const eventsSnap = await eventsQuery.get();
    const events: EventDoc[] = eventsSnap.docs.map((doc) => ({
      id: doc.id,
      ...(doc.data() as Omit<EventDoc, "id">),
    }));

    // 4. Fetch mutual follows for "Friends attending" check (coarse — just who user follows)
    const followingSnap = await db.collection("follows")
      .where("followerId", "==", uid)
      .limit(200)
      .get();
    const followingIds = new Set<string>(
      followingSnap.docs.map((d) => d.data().followeeId as string)
    );

    // 5. User's ageTier claim
    const userRecord = await admin.auth().getUser(uid);
    const ageTierClaim = (userRecord.customClaims as Record<string, string> | undefined)?.ageTier;
    const userAgeTier = ageTierFromClaim(ageTierClaim);

    const currentSeason = getLiturgicalSeason(new Date());

    // 6. Score each event
    const scored: Array<EventDoc & { matchScore: number; matchReasons: string[] }> = [];

    for (const event of events) {
      // Only include events from verified churches
      if (!event.fromVerifiedChurch) continue;

      let score = 0;
      const reasons: string[] = [];

      // Church involvement
      if (event.churchId && followedChurchIds.includes(event.churchId)) {
        score += 30;
        reasons.push("From a church you follow");
      }

      // Coarse geo proximity
      if (coarseGeo && event.location) {
        const latDiff = Math.abs(coarseGeo.lat - event.location.lat);
        const lngDiff = Math.abs(coarseGeo.lng - event.location.lng);
        if (latDiff <= COARSE_PROXIMITY_DEGREES && lngDiff <= COARSE_PROXIMITY_DEGREES) {
          score += 25;
          reasons.push("Near you");
        }
      }

      // Friends attending — reason string only, NO count
      try {
        const rsvpSnap = await db
          .collection("rsvps")
          .doc(event.id)
          .collection("attendees")
          .limit(50)
          .get();
        const attendeeIds = new Set<string>(rsvpSnap.docs.map((d) => d.id));
        const hasFriendsAttending = [...followingIds].some((id) => attendeeIds.has(id));
        if (hasFriendsAttending) {
          score += 20;
          reasons.push("Friends are attending"); // never a count
        }
      } catch {
        // RSVP subcollection may not exist — skip gracefully
      }

      // Age group fit
      if (
        event.ageGroup === "ALL" ||
        !event.ageGroup ||
        event.ageGroup === userAgeTier
      ) {
        score += 15;
        if (event.ageGroup && event.ageGroup !== "ALL") {
          reasons.push("Relevant age group");
        }
      }

      // Liturgical relevance
      if (event.liturgicalTopics && event.liturgicalTopics.length > 0) {
        if (topicsMatchSeason(event.liturgicalTopics, currentSeason)) {
          score += 10;
          reasons.push("Timely for this season");
        }
      }

      scored.push({ ...event, matchScore: score, matchReasons: reasons });
    }

    // 7. Sort descending by matchScore, take top N
    scored.sort((a, b) => b.matchScore - a.matchScore);
    const topEvents = scored.slice(0, maxResults);

    // 8. Shape into IntelligenceCard-compatible response
    const cards: IntelligenceCard[] = topEvents.map((event) => {
      const backingEntity: BackingEntity = {
        kind: "EVENT",
        id: event.id,
        verified: true, // Only verified-church events pass the filter above
      };

      const actions: CardAction[] = [
        {
          rung: "SHOW_UP",
          label: "RSVP",
          handler: "action.rsvpEvent",
          target: event.id,
        },
        {
          rung: "PRAY",
          label: "Pray for this event",
          handler: "action.addToPrayer",
          target: event.id,
        },
      ];

      const expiresAt = event.expiresAt
        ? event.expiresAt.toMillis()
        : event.startTime.toMillis();

      const rankReasons: string[] = [
        `Match score: ${event.matchScore}`,
        ...event.matchReasons,
      ];

      const card: IntelligenceCard = {
        id: `event_card_${event.id}`,
        tier: "COMMUNITY",
        title: event.title,
        summary: [
          event.churchName ? `Hosted by ${event.churchName}` : "Community event",
          ...(event.matchReasons.length > 0 ? [event.matchReasons[0]] : []),
        ].slice(0, 3),
        backingEntity,
        truthLevel: "CHURCH_CONFIRMED",
        matchScore: event.matchScore,
        matchReasons: event.matchReasons,
        actions,
        rankScore: event.matchScore,
        rankReasons,
        formation: {
          finite: true,
          spectacleCounters: false,
        },
        createdAt: now,
        expiresAt,
      };

      return card;
    });

    return { cards };
  }
);
