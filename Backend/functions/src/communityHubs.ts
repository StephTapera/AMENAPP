import { onCall, CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const db = admin.firestore();

// MARK: - Shared helpers

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Must be signed in.");
    return request.auth.uid;
}

function requireAppCheck(request: CallableRequest): void {
    if (request.app == null) {
        throw new HttpsError("failed-precondition", "App Check required.");
    }
}

// MARK: - resolveCommunityObject
// Given a URL (or provider+providerId), find or create a canonical object.

export const resolveCommunityObject = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    requireAuth(request);

    const { url, provider, providerId, objectType, title } = request.data as {
        url?: string;
        provider?: string;
        providerId?: string;
        objectType?: string;
        title?: string;
    };

    if (!url && !(provider && providerId)) {
        throw new Error("Must supply url or provider+providerId");
    }

    // Try to find existing canonical object
    let canonicalObjectId: string | null = null;

    if (provider && providerId) {
        const q = await db.collection("canonicalObjects")
            .where(`providerIds.${provider}`, "==", providerId)
            .limit(1)
            .get();
        if (!q.empty) {
            canonicalObjectId = q.docs[0].id;
        }
    }

    if (!canonicalObjectId && url) {
        const q = await db.collection("canonicalObjects")
            .where("canonicalUrl", "==", url)
            .limit(1)
            .get();
        if (!q.empty) {
            canonicalObjectId = q.docs[0].id;
        }
    }

    // Create if not found
    if (!canonicalObjectId) {
        const newDoc = db.collection("canonicalObjects").doc();
        const providerIds: Record<string, string> = {};
        if (provider && providerId) providerIds[provider] = providerId;

        await newDoc.set({
            id: newDoc.id,
            objectType: objectType ?? "genericLink",
            title: title ?? url ?? "Unknown",
            subtitle: null,
            creatorName: null,
            artworkUrl: null,
            canonicalUrl: url ?? null,
            providerIds,
            primaryProvider: provider ?? null,
            safetyStatus: "needsReview",
            explicitContentState: "unknown",
            totalPostCount: 0,
            activeUserCount: 0,
            hubId: null,
            contentCategory: "general",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        canonicalObjectId = newDoc.id;
    }

    return { canonicalObjectId };
});

// MARK: - createOrJoinObjectHub
// Create a hub for a canonical object if none exists, then join it.

export const createOrJoinObjectHub = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);

    const { canonicalObjectId, action } = request.data as {
        canonicalObjectId: string;
        action: "join" | "leave";
    };

    if (!canonicalObjectId) throw new Error("Missing canonicalObjectId");

    const canonicalRef = db.collection("canonicalObjects").doc(canonicalObjectId);
    const canonicalSnap = await canonicalRef.get();
    if (!canonicalSnap.exists) throw new Error("Canonical object not found");

    const canonicalData = canonicalSnap.data()!;

    // Find or create hub
    let hubId = canonicalData.hubId as string | null;
    if (!hubId) {
        const hubRef = db.collection("communityHubs").doc();
        await hubRef.set({
            id: hubRef.id,
            canonicalObjectId,
            title: canonicalData.title,
            subtitle: canonicalData.subtitle ?? null,
            artworkUrl: canonicalData.artworkUrl ?? null,
            totalMembers: 0,
            weeklyPostCount: 0,
            totalPostCount: 0,
            safetyStatus: canonicalData.safetyStatus ?? "needsReview",
            privacyLevel: "public",
            topicChips: [],
            relatedObjectIds: [],
            discussionPrompts: defaultPromptsFor(canonicalData.contentCategory),
            activitySummary: null,
            contentCategory: canonicalData.contentCategory ?? "general",
            explicitContentState: canonicalData.explicitContentState ?? "unknown",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        hubId = hubRef.id;
        // Backlink canonical object → hub
        await canonicalRef.update({ hubId });
    }

    const membershipRef = db
        .collection("communityHubs").doc(hubId)
        .collection("members").doc(uid);

    if (action === "join") {
        const existing = await membershipRef.get();
        if (!existing.exists) {
            await membershipRef.set({
                hubId,
                userId: uid,
                interactionTypes: ["joined"],
                lastInteractedAt: admin.firestore.FieldValue.serverTimestamp(),
                isMuted: false,
                joinedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            await db.collection("communityHubs").doc(hubId).update({
                totalMembers: admin.firestore.FieldValue.increment(1),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    } else if (action === "leave") {
        await membershipRef.delete();
        await db.collection("communityHubs").doc(hubId).update({
            totalMembers: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    return { hubId, action };
});

// MARK: - getObjectHub
// Returns hub + canonical object + related objects for the hub view.

export const getObjectHub = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    requireAuth(request);

    const { canonicalObjectId } = request.data as { canonicalObjectId: string };
    if (!canonicalObjectId) throw new Error("Missing canonicalObjectId");

    const canonicalSnap = await db.collection("canonicalObjects").doc(canonicalObjectId).get();
    if (!canonicalSnap.exists) throw new HttpsError("not-found", "Canonical object not found.");
    const canonical = { id: canonicalSnap.id, ...canonicalSnap.data() };

    const hubId = (canonical as any).hubId as string | null;
    let hub: Record<string, unknown> | null = null;
    if (hubId) {
        const hubSnap = await db.collection("communityHubs").doc(hubId).get();
        if (hubSnap.exists) {
            hub = { id: hubSnap.id, ...hubSnap.data() };
        }
    }

    // Fetch related objects (same content category, different id). Some local
    // emulator/test Firestore shims do not implement FieldPath.documentId(); the
    // primary hub payload should still resolve in that environment.
    let relatedObjects: Array<Record<string, unknown>> = [];
    const documentIdField = admin.firestore.FieldPath?.documentId?.();
    if (documentIdField) {
        const relatedSnap = await db.collection("canonicalObjects")
            .where("contentCategory", "==", (canonical as any).contentCategory ?? "general")
            .where(documentIdField, "!=", canonicalObjectId)
            .limit(8)
            .get();
        relatedObjects = relatedSnap.docs.map(d => ({ id: d.id, ...d.data() }));
    }

    return { hub, canonicalObject: canonical, relatedObjects };
});

// MARK: - getRelatedObjectHubs

export const getRelatedObjectHubs = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    requireAuth(request);

    const { canonicalObjectId, limit: limitCount = 8 } = request.data as {
        canonicalObjectId: string;
        limit?: number;
    };

    const canonicalSnap = await db.collection("canonicalObjects").doc(canonicalObjectId).get();
    if (!canonicalSnap.exists) return { hubs: [] };

    const category = (canonicalSnap.data() as any)?.contentCategory ?? "general";

    const hubsSnap = await db.collection("communityHubs")
        .where("contentCategory", "==", category)
        .where("privacyLevel", "==", "public")
        .orderBy("totalMembers", "desc")
        .limit(limitCount)
        .get();

    // Fetch user's muted hubs
    const uid = requireAuth(request);
    const mutedSnap = await db.collection("users").doc(uid).collection("mutedHubs").get();
    const mutedHubIds = new Set(mutedSnap.docs.map(d => d.id));

    const ownHubId = (canonicalSnap.data() as any)?.hubId as string | undefined;
    const hubs = hubsSnap.docs
        .filter(d => d.id !== ownHubId)
        .filter(d => {
            const data = d.data() as Record<string, unknown>;
            return data.safetyStatus === "approved" && data.explicitContentState === "clean";
        })
        .filter(d => !mutedHubIds.has(d.id))
        .map(d => ({ id: d.id, ...d.data() }));

    return { hubs };
});

// MARK: - recordObjectInteraction

export const recordObjectInteraction = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);

    const { hubId, interactionType } = request.data as {
        hubId: string;
        interactionType: string;
    };

    const ALLOWED_INTERACTION_TYPES = ["saved", "shared", "prayed", "joined", "commented", "reacted"];
    if (!ALLOWED_INTERACTION_TYPES.includes(interactionType)) {
        throw new HttpsError("invalid-argument", `Invalid interaction type: ${interactionType}`);
    }

    const membershipRef = db
        .collection("communityHubs").doc(hubId)
        .collection("members").doc(uid);

    await membershipRef.set({
        interactionTypes: admin.firestore.FieldValue.arrayUnion(interactionType),
        lastInteractedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    if (interactionType === "prayed") {
        await db.collection("communityHubs").doc(hubId).update({
            "activitySummary.totalPrayerCount": admin.firestore.FieldValue.increment(1),
        });
    }

    return { ok: true };
});

// MARK: - muteObjectHub

export const muteObjectHub = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);

    const { hubId } = request.data as { hubId: string };

    const hubSnap = await db.collection("communityHubs").doc(hubId).get();
    if (!hubSnap.exists) throw new HttpsError("not-found", "Hub not found.");

    const membershipRef = db
        .collection("communityHubs").doc(hubId)
        .collection("members").doc(uid);

    await membershipRef.set({ isMuted: true }, { merge: true });
    return { ok: true };
});

// MARK: - reportHubContent

export const reportHubContent = onCall({ enforceAppCheck: true }, async (request: CallableRequest) => {
    requireAppCheck(request);
    const uid = requireAuth(request);

    const { hubId, reason } = request.data as { hubId: string; reason: string };

    await db.collection("hubContentReports").add({
        hubId,
        reporterUid: uid,
        reason,
        source: "objectHub",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending",
    });

    return { ok: true };
});

// MARK: - indexPostIntoHub (Firestore trigger)
// When a post with a smart attachment is created, increment hub post counts.

export const indexPostIntoHub = onDocumentCreated("posts/{postId}", async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Skip non-public or safety-flagged posts
    if (data.visibility !== "public") return;
    if (data.safetyStatus && data.safetyStatus !== "approved") return;
    if (data.explicitContentState && data.explicitContentState !== "clean") return;

    const canonicalObjectId: string | undefined = data?.smartAttachment?.canonicalObjectId;
    if (!canonicalObjectId) return;

    const canonicalRef = db.collection("canonicalObjects").doc(canonicalObjectId);
    const canonicalSnap = await canonicalRef.get();
    const hubId = canonicalSnap.data()?.hubId as string | undefined;
    if (!hubId) return;

    // Skip if hub is blocked/unsafe
    const hubSnap = await db.collection("communityHubs").doc(hubId).get();
    if (!hubSnap.exists) return;
    const hubData = hubSnap.data() as Record<string, unknown>;
    if (hubData.safetyStatus && hubData.safetyStatus !== "approved") return;
    if (hubData.explicitContentState && hubData.explicitContentState !== "clean") return;

    const hubTotalPostCount = (hubData.totalPostCount as number | undefined) ?? 0;
    const objectType = (canonicalSnap.data()?.objectType as string | undefined) ?? "content";
    const hubLabel = objectType.charAt(0).toUpperCase() + objectType.slice(1) + " Hub";

    await db.collection("communityHubs").doc(hubId).update({
        totalPostCount: admin.firestore.FieldValue.increment(1),
        weeklyPostCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Write communityHubPreview to the post document (safe aggregate only)
    await event.data!.ref.update({
        communityHubPreview: {
            hubId,
            canonicalObjectId,
            aggregateText: `${hubTotalPostCount} public posts`,
            actionText: hubLabel,
        },
    });
});

// MARK: - Weekly hub stats reset (used by scheduledMaintenance.ts)

export async function resetWeeklyHubStats(): Promise<void> {
    const batch = db.batch();
    const hubsSnap = await db.collection("communityHubs")
        .where("weeklyPostCount", ">", 0)
        .get();
    for (const doc of hubsSnap.docs) {
        batch.update(doc.ref, { weeklyPostCount: 0 });
    }
    await batch.commit();
}

// MARK: - Helpers

function defaultPromptsFor(contentCategory?: string): string[] {
    switch (contentCategory) {
    case "worship":
        return [
            "What does this song mean to you in worship?",
            "Share a scripture this brings to mind.",
            "How has this music shaped your prayer life?"
        ];
    case "sermon":
    case "educational":
        return [
            "What was your biggest takeaway?",
            "Which scripture was most powerful for you?",
            "How will you apply this to your week?"
        ];
    case "prayer":
    case "devotional":
        return [
            "What are you believing God for right now?",
            "How is this content shaping your time with God?",
            "Share a prayer this content inspired."
        ];
    default:
        return [
            "What does this mean to you spiritually?",
            "How does this connect to your faith journey?",
            "Share a scripture this brings to mind.",
            "How are you praying about this?"
        ];
    }
}
