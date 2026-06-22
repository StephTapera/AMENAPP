// manageCreatorEvent.ts
// AMEN — Creator Profiles: create / update / delete a creator-hub event.
//
// Callable:
//   manageCreatorEvent — owner/moderator/admin-only write to creatorHubs/{creatorId}/events/{id}
//
// Wire contract: timestamps are ISO-8601 strings on the wire; Firestore stores
// admin.firestore.Timestamp. Incoming ISO is parsed to Timestamp on write; stored
// Timestamp is converted back with tsToISO on read.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
    CreatorHubEvent,
    CreatorHubEventType,
    CreatorHubEventStatus,
    CreatorHubGeo,
    CreatorHubTicketing,
    CREATOR_HUB_FLAGS,
} from "./creatorProfileTypes";
import {
    requireAuth,
    requireManage,
    subCol,
    SUB,
    tsToISO,
    reqString,
    optString,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";

type ManageAction = "create" | "update" | "delete";

const EVENT_TYPES: ReadonlySet<CreatorHubEventType> = new Set<CreatorHubEventType>([
    "sermon", "bibleStudy", "worshipNight", "conference", "class",
    "prayerMeeting", "livestream", "revival", "webinar", "mentorship", "smallGroup",
]);

const EVENT_STATUSES: ReadonlySet<CreatorHubEventStatus> = new Set<CreatorHubEventStatus>([
    "draft", "scheduled", "live", "ended", "canceled",
]);

interface ManageCreatorEventData {
    creatorId?: string;
    action?: ManageAction;
    event?: Partial<CreatorHubEvent>;
    eventId?: string;
}

/** Parse an ISO-8601 string into a Firestore Timestamp, throwing on invalid input. */
function isoToTimestamp(iso: string, field: string): admin.firestore.Timestamp {
    const ms = Date.parse(iso);
    if (Number.isNaN(ms)) {
        throw new HttpsError("invalid-argument", `'${field}' must be an ISO-8601 date string.`);
    }
    return admin.firestore.Timestamp.fromMillis(ms);
}

function validateGeo(geo: unknown): CreatorHubGeo {
    const g = geo as Partial<CreatorHubGeo> | undefined;
    if (
        !g ||
        typeof g.latitude !== "number" ||
        typeof g.longitude !== "number" ||
        !Number.isFinite(g.latitude) ||
        !Number.isFinite(g.longitude)
    ) {
        throw new HttpsError("invalid-argument", "'event.geo' must have numeric latitude/longitude.");
    }
    const out: CreatorHubGeo = { latitude: g.latitude, longitude: g.longitude };
    if (typeof g.locationName === "string" && g.locationName.trim()) {
        out.locationName = g.locationName.trim();
    }
    return out;
}

function validateTicketing(ticketing: unknown): CreatorHubTicketing {
    const t = ticketing as Partial<CreatorHubTicketing> | undefined;
    if (!t || typeof t.isTicketed !== "boolean") {
        throw new HttpsError("invalid-argument", "'event.ticketing.isTicketed' must be a boolean.");
    }
    const out: CreatorHubTicketing = { isTicketed: t.isTicketed };
    if (typeof t.priceCents === "number" && Number.isFinite(t.priceCents)) out.priceCents = Math.floor(t.priceCents);
    if (typeof t.currency === "string" && t.currency.trim()) out.currency = t.currency.trim();
    if (typeof t.url === "string" && t.url.trim()) out.url = t.url.trim();
    return out;
}

function validateStringArray(value: unknown, field: string): string[] {
    if (value === undefined) return [];
    if (!Array.isArray(value) || value.some((v) => typeof v !== "string")) {
        throw new HttpsError("invalid-argument", `'${field}' must be an array of strings.`);
    }
    return (value as string[]).map((s) => s.trim()).filter((s) => s.length > 0);
}

/** Serialize a Firestore event doc into the wire shape (ISO timestamps). */
function serializeEvent(id: string, creatorId: string, data: admin.firestore.DocumentData): CreatorHubEvent {
    const startsAt = tsToISO(data.startsAt);
    if (!startsAt) {
        throw new HttpsError("internal", "Stored event is missing a valid 'startsAt'.");
    }
    const event: CreatorHubEvent = {
        id,
        creatorId,
        type: data.type as CreatorHubEventType,
        title: data.title as string,
        startsAt,
        timeZone: data.timeZone as string,
        speakers: Array.isArray(data.speakers) ? (data.speakers as string[]) : [],
        status: (data.status as CreatorHubEventStatus) ?? "draft",
    };
    const endsAt = tsToISO(data.endsAt);
    if (endsAt) event.endsAt = endsAt;
    if (data.geo) event.geo = data.geo as CreatorHubGeo;
    if (typeof data.registrationUrl === "string") event.registrationUrl = data.registrationUrl;
    if (data.ticketing) event.ticketing = data.ticketing as CreatorHubTicketing;
    if (typeof data.livestreamRef === "string") event.livestreamRef = data.livestreamRef;
    if (typeof data.capacity === "number") event.capacity = data.capacity;
    return event;
}

export const manageCreatorEvent = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<{ ok: true; event?: CreatorHubEvent }> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.eventsEnabled);

        const data = (request.data ?? {}) as ManageCreatorEventData;
        const creatorId = reqString(data, "creatorId");
        const action = data.action;
        if (action !== "create" && action !== "update" && action !== "delete") {
            throw new HttpsError("invalid-argument", "'action' must be create | update | delete.");
        }

        await requireManage(request, creatorId);

        const events = subCol(creatorId, SUB.events);

        if (action === "delete") {
            const eventId = reqString(data, "eventId");
            await events.doc(eventId).delete();
            return { ok: true };
        }

        const input = (data.event ?? {}) as Partial<CreatorHubEvent>;

        if (action === "create") {
            // Required fields.
            const type = reqString(input, "type") as CreatorHubEventType;
            if (!EVENT_TYPES.has(type)) {
                throw new HttpsError("invalid-argument", `Unknown event type '${type}'.`);
            }
            const title = reqString(input, "title");
            const startsAtISO = reqString(input, "startsAt");
            const timeZone = reqString(input, "timeZone");

            let status: CreatorHubEventStatus = "draft";
            if (typeof input.status === "string") {
                if (!EVENT_STATUSES.has(input.status as CreatorHubEventStatus)) {
                    throw new HttpsError("invalid-argument", `Unknown event status '${input.status}'.`);
                }
                status = input.status as CreatorHubEventStatus;
            }

            const docRef = events.doc();
            const write: admin.firestore.DocumentData = {
                creatorId,
                type,
                title,
                startsAt: isoToTimestamp(startsAtISO, "event.startsAt"),
                timeZone,
                speakers: validateStringArray(input.speakers, "event.speakers"),
                status,
                createdAt: admin.firestore.Timestamp.now(),
                createdBy: uid,
            };

            const endsAtISO = optString(input, "endsAt");
            if (endsAtISO) write.endsAt = isoToTimestamp(endsAtISO, "event.endsAt");
            if (input.geo !== undefined) write.geo = validateGeo(input.geo);
            const registrationUrl = optString(input, "registrationUrl");
            if (registrationUrl) write.registrationUrl = registrationUrl;
            if (input.ticketing !== undefined) write.ticketing = validateTicketing(input.ticketing);
            const livestreamRef = optString(input, "livestreamRef");
            if (livestreamRef) write.livestreamRef = livestreamRef;
            if (typeof input.capacity === "number" && Number.isFinite(input.capacity)) {
                write.capacity = Math.floor(input.capacity);
            }

            await docRef.set(write);
            const snap = await docRef.get();
            return { ok: true, event: serializeEvent(docRef.id, creatorId, snap.data() ?? {}) };
        }

        // action === "update"
        const eventId = reqString(data, "eventId");
        const docRef = events.doc(eventId);
        const existing = await docRef.get();
        if (!existing.exists) {
            throw new HttpsError("not-found", "Event does not exist.");
        }

        const merge: admin.firestore.DocumentData = { updatedAt: admin.firestore.Timestamp.now() };

        if (input.type !== undefined) {
            if (!EVENT_TYPES.has(input.type as CreatorHubEventType)) {
                throw new HttpsError("invalid-argument", `Unknown event type '${input.type}'.`);
            }
            merge.type = input.type;
        }
        const title = optString(input, "title");
        if (title) merge.title = title;
        const startsAtISO = optString(input, "startsAt");
        if (startsAtISO) merge.startsAt = isoToTimestamp(startsAtISO, "event.startsAt");
        const timeZone = optString(input, "timeZone");
        if (timeZone) merge.timeZone = timeZone;
        const endsAtISO = optString(input, "endsAt");
        if (endsAtISO) merge.endsAt = isoToTimestamp(endsAtISO, "event.endsAt");
        if (input.geo !== undefined) merge.geo = validateGeo(input.geo);
        if (input.registrationUrl !== undefined) {
            merge.registrationUrl = optString(input, "registrationUrl") ?? "";
        }
        if (input.ticketing !== undefined) merge.ticketing = validateTicketing(input.ticketing);
        if (input.livestreamRef !== undefined) {
            merge.livestreamRef = optString(input, "livestreamRef") ?? "";
        }
        if (typeof input.capacity === "number" && Number.isFinite(input.capacity)) {
            merge.capacity = Math.floor(input.capacity);
        }
        if (input.speakers !== undefined) merge.speakers = validateStringArray(input.speakers, "event.speakers");
        if (input.status !== undefined) {
            if (!EVENT_STATUSES.has(input.status as CreatorHubEventStatus)) {
                throw new HttpsError("invalid-argument", `Unknown event status '${input.status}'.`);
            }
            merge.status = input.status;
        }

        await docRef.set(merge, { merge: true });
        const snap = await docRef.get();
        return { ok: true, event: serializeEvent(docRef.id, creatorId, snap.data() ?? {}) };
    }
);
