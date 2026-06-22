import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

// setCommunitySaved
//
// P1-Phase-F: Server-authoritative Save/Unsave for community-level
// bookmarking. Writes are server-only — Firestore rules deny direct client
// writes to users/{uid}/savedCommunities/{communityKey}.
//
// Validates that:
//   - the caller is authenticated and App-Checked
//   - the target community exists
//   - the caller can see the community (public, or member of a private one)
// Then performs an idempotent set/delete.

type CommunityType = "covenant" | "hub" | "ark";

interface Input {
    communityType: CommunityType;
    communityId: string;
    saved: boolean;
}

const ALLOWED_TYPES: ReadonlySet<CommunityType> = new Set(["covenant", "hub", "ark"]);

function communityCollectionFor(type: CommunityType): string {
    switch (type) {
        case "covenant": return "covenants";
        case "hub":      return "communityHubs";
        case "ark":      return "arkCommunities";
    }
}

// Composite key used as the Firestore document id under
// users/{uid}/savedCommunities/{key}. Keeps the type explicit so we don't
// collide between a Covenant and a Hub that share the same string id.
function savedKeyFor(type: CommunityType, id: string): string {
    return `${type}_${id}`;
}

interface VisibilityCheck {
    visible: boolean;
    titleSnapshot: string | null;
    avatarUrlSnapshot: string | null;
    visibilitySnapshot: string | null;
}

async function checkCommunityVisibility(
    db: admin.firestore.Firestore,
    uid: string,
    type: CommunityType,
    id: string
): Promise<VisibilityCheck> {
    const docSnap = await db.collection(communityCollectionFor(type)).doc(id).get();
    if (!docSnap.exists) {
        return { visible: false, titleSnapshot: null, avatarUrlSnapshot: null, visibilitySnapshot: null };
    }
    const data = docSnap.data() ?? {};

    const titleSnapshot   = (data.title as string | undefined) ?? (data.name as string | undefined) ?? null;
    const avatarUrlSnapshot = (data.artworkUrl as string | undefined) ?? (data.avatarUrl as string | undefined) ?? null;

    let visibilitySnapshot: string;
    let visible: boolean;

    if (type === "covenant") {
        const isPublic = data.isPublic !== false;
        visibilitySnapshot = isPublic ? "public" : "private";
        if (isPublic) {
            visible = true;
        } else {
            // Private covenant — must be a member.
            const memberSnap = await db
                .collection("covenants").doc(id)
                .collection("members").doc(uid)
                .get();
            visible = memberSnap.exists;
        }
    } else if (type === "hub") {
        const privacy = String(data.privacyLevel ?? data.visibility ?? "public");
        visibilitySnapshot = privacy;
        visible = privacy === "public";
    } else {
        // ark
        const isPrivate = data.isPrivate === true;
        visibilitySnapshot = isPrivate ? "private" : "public";
        if (!isPrivate) {
            visible = true;
        } else {
            // Private ark — must be a member or creator/admin.
            const creatorId = String(data.creatorId ?? "");
            const adminIds: string[] = Array.isArray(data.adminIds) ? (data.adminIds as string[]) : [];
            if (creatorId === uid || adminIds.includes(uid)) {
                visible = true;
            } else {
                const memberSnap = await db
                    .collection("arkCommunities").doc(id)
                    .collection("members").doc(uid)
                    .get();
                visible = memberSnap.exists;
            }
        }
    }

    return { visible, titleSnapshot, avatarUrlSnapshot, visibilitySnapshot };
}

// Exported for unit testing.
export async function setCommunitySavedHandler(
    uid: string | null,
    appCheckPresent: boolean,
    data: Partial<Input>,
    db: admin.firestore.Firestore = admin.firestore()
): Promise<{ saved: boolean; communityKey: string }> {
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    if (!appCheckPresent) throw new HttpsError("failed-precondition", "App Check required.");

    const communityType = data.communityType as CommunityType | undefined;
    const communityId = (data.communityId ?? "").trim();
    const saved = data.saved === true;

    if (!communityType || !ALLOWED_TYPES.has(communityType)) {
        throw new HttpsError("invalid-argument", "communityType must be covenant, hub, or ark.");
    }
    if (!communityId) {
        throw new HttpsError("invalid-argument", "communityId is required.");
    }

    await enforceRateLimit(uid, [
        RATE_LIMITS.COMMUNITY_SAVE_PER_MINUTE,
        RATE_LIMITS.COMMUNITY_SAVE_PER_DAY,
    ]);

    const vis = await checkCommunityVisibility(db, uid, communityType, communityId);
    if (!vis.visible) {
        // Either community doesn't exist or caller cannot see it. Either way,
        // do not write — protects against private-community probing.
        throw new HttpsError("not-found", "Community not found or not accessible.");
    }

    const key = savedKeyFor(communityType, communityId);
    const ref = db.collection("users").doc(uid).collection("savedCommunities").doc(key);

    if (saved) {
        await ref.set({
            communityId,
            communityType,
            saved: true,
            titleSnapshot: vis.titleSnapshot,
            avatarUrlSnapshot: vis.avatarUrlSnapshot,
            visibilitySnapshot: vis.visibilitySnapshot,
            savedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    } else {
        // Idempotent unsave — deleting a missing doc is a no-op for our purposes.
        await ref.delete().catch(() => undefined);
    }

    logger.info("[setCommunitySaved] ok", {
        uid,
        communityType,
        communityKey: key,
        saved,
    });

    return { saved, communityKey: key };
}

// ── Cloud Function ────────────────────────────────────────────────────────────

export const setCommunitySaved = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        return setCommunitySavedHandler(
            request.auth?.uid ?? null,
            request.app != null,
            (request.data ?? {}) as Partial<Input>
        );
    }
);
