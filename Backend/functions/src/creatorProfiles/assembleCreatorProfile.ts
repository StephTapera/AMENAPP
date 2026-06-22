// assembleCreatorProfile.ts
// AMEN — Creator Profiles: the single first-paint round trip.
// Loads the hub profile + a CalmCap-bounded first page of every module, resolves
// the server-authoritative hero state + featured module, and reports pill counts.
//
// CalmCap: every page is bounded to maxItemsPerShelf (12). Ordering is by time/status
// only — never by engagement signals. UGC (prayer/community) is approved-only.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Query, QueryDocumentSnapshot, DocumentData } from "firebase-admin/firestore";

import {
    CREATOR_HUB_FLAGS,
    CREATOR_HUB_CALMCAP_V1,
    CreatorHubProfile,
    CreatorHubProfilePayload,
    CreatorHubHeroState,
    CreatorHubFeaturedModule,
    CreatorHubPillCounts,
    CreatorHubFirstPages,
    CreatorHubEvent,
    CreatorHubTeaching,
    CreatorHubResource,
    CreatorHubPrayerRequest,
    CreatorHubCommunityPost,
    CreatorHubCourse,
    CreatorHubModuleKind,
} from "./creatorProfileTypes";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    requireAuth,
    db,
    hubRef,
    subCol,
    COLL,
    SUB,
    reqString,
    nowISO,
} from "./creatorProfilesShared";
import {
    mapProfile,
    mapEvent,
    mapTeaching,
    mapResource,
    mapPrayerRequest,
    mapCommunityPost,
    mapCourse,
} from "./creatorProfileMappers";

const PAGE = CREATOR_HUB_CALMCAP_V1.maxItemsPerShelf; // 12

async function countOrLength(q: Query<DocumentData>): Promise<number> {
    try {
        const agg = await q.count().get();
        return agg.data().count;
    } catch {
        const snap = await q.get();
        return snap.size;
    }
}

export const assembleCreatorProfile = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<CreatorHubProfilePayload> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.profilesEnabled);

        const creatorId = reqString(request.data, "creatorId");

        const profileSnap = await hubRef(creatorId).get();
        if (!profileSnap.exists) {
            throw new HttpsError("not-found", "Creator hub not found.");
        }
        const profile: CreatorHubProfile = mapProfile(profileSnap.id, profileSnap.data() ?? {});

        // Base queries (time/status ordering only — no engagement-bait).
        const eventsQ = subCol(creatorId, SUB.events)
            .where("status", "in", ["scheduled", "live"])
            .orderBy("startsAt", "asc")
            .limit(PAGE);
        const teachingsQ = subCol(creatorId, SUB.teachings)
            .orderBy("createdAt", "desc")
            .limit(PAGE);
        const resourcesQ = subCol(creatorId, SUB.resources)
            .orderBy("createdAt", "desc")
            .limit(PAGE);
        const prayerQ = subCol(creatorId, SUB.prayerRequests)
            .where("status", "==", "approved")
            .where("isPrivate", "==", false)
            .orderBy("createdAt", "desc")
            .limit(PAGE);
        const communityQ = subCol(creatorId, SUB.communityPosts)
            .where("status", "==", "approved")
            .orderBy("createdAt", "desc")
            .limit(PAGE);
        const coursesQ = subCol(creatorId, SUB.courses)
            .orderBy("createdAt", "desc")
            .limit(PAGE);

        const followDocId = `${uid}_${creatorId}`;

        const [
            eventsSnap,
            teachingsSnap,
            resourcesSnap,
            prayerSnap,
            communitySnap,
            coursesSnap,
            eventsCount,
            teachingsCount,
            resourcesCount,
            prayerCount,
            communityCount,
            coursesCount,
            followSnap,
        ] = await Promise.all([
            eventsQ.get(),
            teachingsQ.get(),
            resourcesQ.get(),
            prayerQ.get(),
            communityQ.get(),
            coursesQ.get(),
            countOrLength(
                subCol(creatorId, SUB.events).where("status", "in", ["scheduled", "live"])
            ),
            countOrLength(subCol(creatorId, SUB.teachings)),
            countOrLength(subCol(creatorId, SUB.resources)),
            countOrLength(
                subCol(creatorId, SUB.prayerRequests)
                    .where("status", "==", "approved")
                    .where("isPrivate", "==", false)
            ),
            countOrLength(
                subCol(creatorId, SUB.communityPosts).where("status", "==", "approved")
            ),
            countOrLength(subCol(creatorId, SUB.courses)),
            db().collection(COLL.follows).doc(followDocId).get(),
        ]);

        const events: CreatorHubEvent[] = eventsSnap.docs.map((d) =>
            mapEvent(d.id, creatorId, d.data())
        );
        const teachings: CreatorHubTeaching[] = teachingsSnap.docs.map((d) =>
            mapTeaching(d.id, creatorId, d.data())
        );
        const resources: CreatorHubResource[] = resourcesSnap.docs.map((d) =>
            mapResource(d.id, creatorId, d.data())
        );
        const prayer: CreatorHubPrayerRequest[] = prayerSnap.docs.map((d) =>
            mapPrayerRequest(d.id, creatorId, d.data())
        );
        const community: CreatorHubCommunityPost[] = communitySnap.docs.map((d) =>
            mapCommunityPost(d.id, creatorId, d.data())
        );
        const courses: CreatorHubCourse[] = coursesSnap.docs.map((d) =>
            mapCourse(d.id, creatorId, d.data())
        );

        const liveEvent = events.find((e) => e.status === "live");
        const nextEvent = events.find((e) => e.status === "scheduled");
        const latestTeaching = teachings[0];
        const latestResource = resources[0];
        const featuredCourse = courses[0];
        const openPrayerRequests = prayerCount;

        const resolveHero = (): CreatorHubHeroState => {
            if (liveEvent) return { type: "live", data: { event: liveEvent } };
            if (nextEvent) return { type: "nextEvent", data: { event: nextEvent } };
            if (latestTeaching) return { type: "latestTeaching", data: { teaching: latestTeaching } };
            if (openPrayerRequests > 0) return { type: "prayer", data: { openRequests: openPrayerRequests } };
            if (latestResource) return { type: "resource", data: { resource: latestResource } };
            return { type: "idle", data: {} };
        };
        const heroState: CreatorHubHeroState = resolveHero();

        const resolveFeatured = (): CreatorHubFeaturedModule | null => {
            if (liveEvent) return { type: "live", data: { event: liveEvent } };
            if (nextEvent) return { type: "nextEvent", data: { event: nextEvent } };
            if (latestTeaching) return { type: "latestTeaching", data: { teaching: latestTeaching } };
            if (latestResource) return { type: "newResource", data: { resource: latestResource } };
            if (featuredCourse) return { type: "featuredCourse", data: { course: featuredCourse } };
            return null;
        };
        const featuredModule: CreatorHubFeaturedModule | null = resolveFeatured();

        const pillCounts: CreatorHubPillCounts = {
            events: eventsCount,
            teachings: teachingsCount,
            resources: resourcesCount,
            prayer: prayerCount,
            community: communityCount,
            courses: coursesCount,
        };

        const cursors: Partial<Record<CreatorHubModuleKind, string>> = {};
        const lastId = (snap: { docs: QueryDocumentSnapshot[]; size: number }): string | undefined =>
            snap.size >= PAGE ? snap.docs[snap.docs.length - 1].id : undefined;
        const setCursor = (module: CreatorHubModuleKind, id: string | undefined) => {
            if (id) cursors[module] = id;
        };
        setCursor("events", lastId(eventsSnap));
        setCursor("teachings", lastId(teachingsSnap));
        setCursor("resources", lastId(resourcesSnap));
        setCursor("prayer", lastId(prayerSnap));
        setCursor("community", lastId(communitySnap));
        setCursor("courses", lastId(coursesSnap));

        const firstPages: CreatorHubFirstPages = {
            events,
            teachings,
            resources,
            prayer,
            community,
            courses,
            cursors,
        };

        return {
            profile,
            heroState,
            featuredModule,
            pillCounts,
            firstPages,
            calmCap: CREATOR_HUB_CALMCAP_V1,
            viewerFollows: followSnap.exists,
            assembledAt: nowISO(),
        };
    }
);
