// rsvpCreatorEvent.ts
// AMEN — Creator Profiles: RSVP to (or cancel) a creator-hub event, with a
// server-computed calendar payload and a smart "leave-by" travel reminder.
//
// Callable:
//   rsvpCreatorEvent — any authed user may RSVP; writes
//   creatorHubs/{creatorId}/eventRsvps/{eventId}_{uid}.
//
// Wire contract: timestamps are ISO-8601 strings on the wire; Firestore stores
// admin.firestore.Timestamp (converted with tsToISO on read).

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CreatorHubGeo, CREATOR_HUB_FLAGS } from "./creatorProfileTypes";
import {
    requireAuth,
    subCol,
    SUB,
    tsToISO,
    reqString,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";

interface RsvpCreatorEventData {
    creatorId?: string;
    eventId?: string;
    rsvp?: boolean;
    originLat?: number;
    originLng?: number;
}

interface CalendarPayload {
    title: string;
    startsAt: string;
    endsAt?: string;
    timeZone: string;
    location?: string;
}

interface ReminderPayload {
    leaveByISO: string;
    travelMinutes?: number;
}

const ASSUMED_SPEED_KMH = 40;
const TRAVEL_BUFFER_MIN = 15;
const DEFAULT_LEAD_MIN = 30;
const EARTH_RADIUS_KM = 6371;

function toRadians(deg: number): number {
    return (deg * Math.PI) / 180;
}

/** Great-circle (straight-line) distance in km between two coordinates. */
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const dLat = toRadians(lat2 - lat1);
    const dLng = toRadians(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLng / 2) ** 2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return EARTH_RADIUS_KM * c;
}

export const rsvpCreatorEvent = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<{ ok: true; calendar: CalendarPayload; reminder: ReminderPayload }> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.eventsEnabled);

        const data = (request.data ?? {}) as RsvpCreatorEventData;
        const creatorId = reqString(data, "creatorId");
        const eventId = reqString(data, "eventId");

        // Read the event first — we need it for the calendar + reminder payload,
        // and to refuse RSVPs against events that do not exist.
        const eventSnap = await subCol(creatorId, SUB.events).doc(eventId).get();
        if (!eventSnap.exists) {
            throw new HttpsError("not-found", "Event does not exist.");
        }
        const event = eventSnap.data() ?? {};

        const startsAtISO = tsToISO(event.startsAt);
        if (!startsAtISO) {
            throw new HttpsError("failed-precondition", "Event is missing a valid start time.");
        }
        const startsAtMs = Date.parse(startsAtISO);

        // Write or clear the RSVP. Any authed user may do this (no requireManage).
        const rsvpRef = subCol(creatorId, SUB.eventRsvps).doc(`${eventId}_${uid}`);
        if (data.rsvp === false) {
            await rsvpRef.delete();
        } else {
            await rsvpRef.set({
                uid,
                eventId,
                rsvpedAt: admin.firestore.Timestamp.now(),
            });
        }

        // Calendar payload.
        const geo = event.geo as CreatorHubGeo | undefined;
        const calendar: CalendarPayload = {
            title: typeof event.title === "string" ? event.title : "Event",
            startsAt: startsAtISO,
            timeZone: typeof event.timeZone === "string" ? event.timeZone : "UTC",
        };
        const endsAtISO = tsToISO(event.endsAt);
        if (endsAtISO) calendar.endsAt = endsAtISO;
        if (geo?.locationName) calendar.location = geo.locationName;

        // Smart-reminder: estimate travel time from origin → event geo when both exist.
        let reminder: ReminderPayload;
        const hasGeo =
            geo !== undefined &&
            typeof geo.latitude === "number" &&
            typeof geo.longitude === "number";
        const hasOrigin =
            typeof data.originLat === "number" &&
            typeof data.originLng === "number" &&
            Number.isFinite(data.originLat) &&
            Number.isFinite(data.originLng);

        if (hasGeo && hasOrigin) {
            const distanceKm = haversineKm(
                data.originLat as number,
                data.originLng as number,
                geo.latitude,
                geo.longitude
            );
            const travelMinutes = Math.ceil((distanceKm / ASSUMED_SPEED_KMH) * 60);
            const leaveByMs = startsAtMs - (travelMinutes + TRAVEL_BUFFER_MIN) * 60_000;
            reminder = {
                leaveByISO: new Date(leaveByMs).toISOString(),
                travelMinutes,
            };
        } else {
            const leaveByMs = startsAtMs - DEFAULT_LEAD_MIN * 60_000;
            reminder = { leaveByISO: new Date(leaveByMs).toISOString() };
        }

        return { ok: true, calendar, reminder };
    }
);
