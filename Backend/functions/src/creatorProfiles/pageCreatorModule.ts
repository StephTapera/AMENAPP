// pageCreatorModule.ts
// AMEN — Creator Profiles: cursor-paginated "load a little more" for one module.
// NOT infinite scroll — the client pages explicitly. CalmCap bounds each page.
// UGC modules (prayer/community) are approved-only; prayer additionally !isPrivate.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Query, DocumentData } from "firebase-admin/firestore";

import {
    CREATOR_HUB_FLAGS,
    CreatorHubModuleKind,
    CreatorHubModulePage,
    CreatorHubEvent,
    CreatorHubTeaching,
    CreatorHubResource,
    CreatorHubPrayerRequest,
    CreatorHubCommunityPost,
    CreatorHubCourse,
} from "./creatorProfileTypes";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    requireAuth,
    subCol,
    SUB,
    reqString,
    optString,
    pageLimit,
} from "./creatorProfilesShared";
import {
    mapEvent,
    mapTeaching,
    mapResource,
    mapPrayerRequest,
    mapCommunityPost,
    mapCourse,
} from "./creatorProfileMappers";

type ModuleItem =
    | CreatorHubEvent
    | CreatorHubTeaching
    | CreatorHubResource
    | CreatorHubPrayerRequest
    | CreatorHubCommunityPost
    | CreatorHubCourse;

const PAGEABLE: CreatorHubModuleKind[] = [
    "events", "teachings", "resources", "prayer", "community", "courses",
];

/** Maps a module to its subcollection + base (time/status-only) ordered query. */
function baseQueryFor(creatorId: string, module: CreatorHubModuleKind): Query<DocumentData> {
    switch (module) {
        case "events":
            return subCol(creatorId, SUB.events)
                .where("status", "in", ["scheduled", "live"])
                .orderBy("startsAt", "asc");
        case "teachings":
            return subCol(creatorId, SUB.teachings).orderBy("createdAt", "desc");
        case "resources":
            return subCol(creatorId, SUB.resources).orderBy("createdAt", "desc");
        case "prayer":
            return subCol(creatorId, SUB.prayerRequests)
                .where("status", "==", "approved")
                .where("isPrivate", "==", false)
                .orderBy("createdAt", "desc");
        case "community":
            return subCol(creatorId, SUB.communityPosts)
                .where("status", "==", "approved")
                .orderBy("createdAt", "desc");
        case "courses":
            return subCol(creatorId, SUB.courses).orderBy("createdAt", "desc");
        default:
            throw new HttpsError("invalid-argument", `Module is not pageable: ${module}`);
    }
}

function mapDocs(
    creatorId: string,
    module: CreatorHubModuleKind,
    docs: FirebaseFirestore.QueryDocumentSnapshot[]
): ModuleItem[] {
    switch (module) {
        case "events":
            return docs.map((d) => mapEvent(d.id, creatorId, d.data()));
        case "teachings":
            return docs.map((d) => mapTeaching(d.id, creatorId, d.data()));
        case "resources":
            return docs.map((d) => mapResource(d.id, creatorId, d.data()));
        case "prayer":
            return docs.map((d) => mapPrayerRequest(d.id, creatorId, d.data()));
        case "community":
            return docs.map((d) => mapCommunityPost(d.id, creatorId, d.data()));
        case "courses":
            return docs.map((d) => mapCourse(d.id, creatorId, d.data()));
        default:
            throw new HttpsError("invalid-argument", `Module is not pageable: ${module}`);
    }
}

export const pageCreatorModule = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<CreatorHubModulePage<ModuleItem>> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.profilesEnabled);
        void uid;

        const creatorId = reqString(request.data, "creatorId");
        const module = reqString(request.data, "module") as CreatorHubModuleKind;
        if (!PAGEABLE.includes(module)) {
            throw new HttpsError("invalid-argument", `Unsupported module: ${module}`);
        }
        const cursor = optString(request.data, "cursor");
        const limit = pageLimit(request.data);

        let query = baseQueryFor(creatorId, module);

        if (cursor) {
            // Cursor is a document id within this module's subcollection. Anchor
            // startAfter to its snapshot so ordering stays consistent.
            const cursorSnap = await collectionForModule(creatorId, module).doc(cursor).get();
            if (cursorSnap.exists) {
                query = query.startAfter(cursorSnap);
            }
        }

        const snap = await query.limit(limit).get();
        const items = mapDocs(creatorId, module, snap.docs);

        const nextCursor =
            snap.size >= limit ? snap.docs[snap.docs.length - 1].id : undefined;

        return { module, items, nextCursor };
    }
);

/** The raw subcollection for a module (used to load the cursor document snapshot). */
function collectionForModule(creatorId: string, module: CreatorHubModuleKind) {
    switch (module) {
        case "events": return subCol(creatorId, SUB.events);
        case "teachings": return subCol(creatorId, SUB.teachings);
        case "resources": return subCol(creatorId, SUB.resources);
        case "prayer": return subCol(creatorId, SUB.prayerRequests);
        case "community": return subCol(creatorId, SUB.communityPosts);
        case "courses": return subCol(creatorId, SUB.courses);
        default:
            throw new HttpsError("invalid-argument", `Module is not pageable: ${module}`);
    }
}
