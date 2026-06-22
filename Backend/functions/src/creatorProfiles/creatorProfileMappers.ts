// creatorProfileMappers.ts
// AMEN — Creator Profiles: Firestore document → wire contract mappers.
// Firestore stores Timestamps; the wire shape uses ISO-8601 strings (tsToISO).
// These are pure deserializers shared by assembleCreatorProfile / pageCreatorModule /
// searchCreatorTeachings. They depend only on documented contract types + tsToISO.

import {
    CreatorHubProfile,
    CreatorHubEvent,
    CreatorHubTeaching,
    CreatorHubResource,
    CreatorHubPrayerRequest,
    CreatorHubCommunityPost,
    CreatorHubCourse,
    CreatorHubMediaRef,
    CreatorHubLink,
    CreatorHubGeo,
    CreatorHubTicketing,
    CreatorHubBadge,
    CreatorHubAudienceTag,
    CreatorHubModerationStatus,
    CreatorHubEventType,
    CreatorHubEventStatus,
    CreatorHubResourceKind,
    CreatorHubCommunityKind,
    CreatorHubProgressModel,
    CreatorHubCourseModule,
    CreatorHubLesson,
    CREATOR_HUB_CALMCAP_V1,
} from "./creatorProfileTypes";
import { tsToISO } from "./creatorProfilesShared";

// ── Primitive coercions (defensive — never trust stored shape) ───────────────

function str(v: unknown, fallback = ""): string {
    return typeof v === "string" ? v : fallback;
}

function num(v: unknown, fallback = 0): number {
    return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

function bool(v: unknown, fallback = false): boolean {
    return typeof v === "boolean" ? v : fallback;
}

function strArray(v: unknown): string[] {
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

function optStr(v: unknown): string | undefined {
    return typeof v === "string" && v.length > 0 ? v : undefined;
}

function optNum(v: unknown): number | undefined {
    return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

function moderation(v: unknown): CreatorHubModerationStatus {
    const allowed: CreatorHubModerationStatus[] = [
        "quarantined", "pending", "approved", "rejected", "hidden",
    ];
    return allowed.includes(v as CreatorHubModerationStatus)
        ? (v as CreatorHubModerationStatus)
        : "quarantined";
}

function mediaRef(v: unknown): CreatorHubMediaRef | undefined {
    if (!v || typeof v !== "object") return undefined;
    const d = v as Record<string, unknown>;
    const kind = d.kind;
    if (kind !== "image" && kind !== "video" && kind !== "audio") return undefined;
    return {
        kind,
        storagePath: str(d.storagePath),
        aspectRatio: optStr(d.aspectRatio),
        durationSec: optNum(d.durationSec),
        moderation: moderation(d.moderation),
    };
}

function links(v: unknown): CreatorHubLink[] {
    if (!Array.isArray(v)) return [];
    return v
        .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
        .map((d) => ({
            label: str(d.label),
            url: str(d.url),
            kind: ([
                "website", "giving", "youtube", "podcast", "social", "app", "other",
            ].includes(d.kind as string)
                ? (d.kind as CreatorHubLink["kind"])
                : "other"),
        }));
}

function geo(v: unknown): CreatorHubGeo | undefined {
    if (!v || typeof v !== "object") return undefined;
    const d = v as Record<string, unknown>;
    if (typeof d.latitude !== "number" || typeof d.longitude !== "number") return undefined;
    return {
        latitude: d.latitude,
        longitude: d.longitude,
        locationName: optStr(d.locationName),
    };
}

function ticketing(v: unknown): CreatorHubTicketing | undefined {
    if (!v || typeof v !== "object") return undefined;
    const d = v as Record<string, unknown>;
    return {
        isTicketed: bool(d.isTicketed),
        priceCents: optNum(d.priceCents),
        currency: optStr(d.currency),
        url: optStr(d.url),
    };
}

// ── Document mappers ─────────────────────────────────────────────────────────

export function mapProfile(id: string, d: Record<string, unknown>): CreatorHubProfile {
    const audience = d.audienceTag;
    const audienceTag: CreatorHubAudienceTag =
        audience === "youth" || audience === "kids" || audience === "mixed"
            ? audience
            : "general";
    const badges: CreatorHubBadge[] = Array.isArray(d.badges)
        ? (d.badges.filter((b): b is CreatorHubBadge =>
            ["live", "nextEvent", "prayer", "resource", "verified"].includes(b as string)))
        : [];
    return {
        id,
        displayName: str(d.displayName),
        handle: str(d.handle),
        roleLabels: strArray(d.roleLabels),
        verified: bool(d.verified),
        heroMedia: mediaRef(d.heroMedia),
        badges,
        links: links(d.links),
        audienceTag,
        // Per-creator override is allowed; absent → platform CalmCap v1.
        calmCapProfile:
            d.calmCapProfile && typeof d.calmCapProfile === "object"
                ? {
                      maxShelves: num((d.calmCapProfile as Record<string, unknown>).maxShelves, CREATOR_HUB_CALMCAP_V1.maxShelves),
                      maxItemsPerShelf: num((d.calmCapProfile as Record<string, unknown>).maxItemsPerShelf, CREATOR_HUB_CALMCAP_V1.maxItemsPerShelf),
                      infiniteScroll: false,
                      sessionSoftLimitSeconds: num((d.calmCapProfile as Record<string, unknown>).sessionSoftLimitSeconds, CREATOR_HUB_CALMCAP_V1.sessionSoftLimitSeconds),
                  }
                : CREATOR_HUB_CALMCAP_V1,
    };
}

export function mapEvent(id: string, creatorId: string, d: Record<string, unknown>): CreatorHubEvent {
    const type = d.type as CreatorHubEventType;
    const status = d.status as CreatorHubEventStatus;
    return {
        id,
        creatorId,
        type,
        title: str(d.title),
        startsAt: tsToISO(d.startsAt) ?? "",
        timeZone: str(d.timeZone, "UTC"),
        endsAt: tsToISO(d.endsAt),
        geo: geo(d.geo),
        registrationUrl: optStr(d.registrationUrl),
        ticketing: ticketing(d.ticketing),
        livestreamRef: optStr(d.livestreamRef),
        capacity: optNum(d.capacity),
        speakers: strArray(d.speakers),
        status,
    };
}

export function mapTeaching(id: string, creatorId: string, d: Record<string, unknown>): CreatorHubTeaching {
    return {
        id,
        creatorId,
        title: str(d.title),
        video: mediaRef(d.video),
        audio: mediaRef(d.audio),
        transcriptRef: optStr(d.transcriptRef),
        notes: optStr(d.notes),
        outline: strArray(d.outline),
        scriptureRefs: strArray(d.scriptureRefs),
        topics: strArray(d.topics),
        series: optStr(d.series),
        speakers: strArray(d.speakers),
        aiSummaryRef: optStr(d.aiSummaryRef),
        durationSec: num(d.durationSec),
    };
}

export function mapResource(id: string, creatorId: string, d: Record<string, unknown>): CreatorHubResource {
    const kind = d.kind as CreatorHubResourceKind;
    return {
        id,
        creatorId,
        kind,
        title: str(d.title),
        fileRef: mediaRef(d.fileRef),
        externalUrl: optStr(d.externalUrl),
        topics: strArray(d.topics),
    };
}

export function mapPrayerRequest(id: string, creatorId: string, d: Record<string, unknown>): CreatorHubPrayerRequest {
    return {
        id,
        creatorId,
        authorId: str(d.authorId),
        body: str(d.body),
        isPrivate: bool(d.isPrivate),
        status: moderation(d.status),
        prayedCount: num(d.prayedCount),
        praiseReport: optStr(d.praiseReport),
    };
}

export function mapCommunityPost(id: string, creatorId: string, d: Record<string, unknown>): CreatorHubCommunityPost {
    const kind = ([
        "question", "testimony", "studyNote", "eventDiscussion",
    ].includes(d.kind as string)
        ? (d.kind as CreatorHubCommunityKind)
        : "question");
    return {
        id,
        creatorId,
        authorId: str(d.authorId),
        kind,
        body: str(d.body),
        parentRef: optStr(d.parentRef),
        status: moderation(d.status),
    };
}

function lesson(v: unknown): CreatorHubLesson {
    const d = (v && typeof v === "object" ? v : {}) as Record<string, unknown>;
    return {
        id: str(d.id),
        title: str(d.title),
        teachingRef: optStr(d.teachingRef),
        durationSec: optNum(d.durationSec),
    };
}

function courseModule(v: unknown): CreatorHubCourseModule {
    const d = (v && typeof v === "object" ? v : {}) as Record<string, unknown>;
    return {
        id: str(d.id),
        title: str(d.title),
        lessons: Array.isArray(d.lessons) ? d.lessons.map(lesson) : [],
    };
}

export function mapCourse(id: string, creatorId: string, d: Record<string, unknown>): CreatorHubCourse {
    const progressModel: CreatorHubProgressModel =
        d.progressModel === "freeform" ? "freeform" : "linear";
    return {
        id,
        creatorId,
        title: str(d.title),
        modules: Array.isArray(d.modules) ? d.modules.map(courseModule) : [],
        progressModel,
    };
}
