// spaces/eventBroadcast.ts
//
// Event and announcement broadcast callables for AMEN Spaces.
//
// Callables:
//   broadcastSpaceEvent        — creates a new event in a space (host-only)
//   broadcastSpaceAnnouncement — sends an announcement to space members (host-only)

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

// ── Interfaces ────────────────────────────────────────────────────────────────

interface BroadcastSpaceEventInput {
    spaceId: string;
    title: string;
    description?: string;
    startsAt?: string;
    endsAt?: string;
    isVirtual?: boolean;
    locationName?: string;
    locationURL?: string;
    maxAttendees?: number;
    [key: string]: unknown;
}

interface BroadcastSpaceAnnouncementInput {
    spaceId: string;
    message: string;
    scope: "all" | "tier" | "selected";
    priority: "normal" | "high" | "urgent";
    scheduledAt?: string;
    eventId?: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function assertSpaceHost(
    db: FirebaseFirestore.Firestore,
    spaceId: string,
    uid: string
): Promise<void> {
    const spaceSnap = await db.doc(`spaces/${spaceId}`).get();
    if (!spaceSnap.exists) {
        throw new HttpsError("not-found", "Space not found.");
    }
    const createdBy = spaceSnap.data()?.createdBy as string | undefined;
    if (createdBy !== uid) {
        throw new HttpsError("permission-denied", "Only the space host can perform this action.");
    }
}

function validateSpaceId(spaceId: unknown): string {
    if (typeof spaceId !== "string" || !spaceId.trim()) {
        throw new HttpsError("invalid-argument", "spaceId is required.");
    }
    return spaceId.trim();
}

// ── broadcastSpaceEvent ───────────────────────────────────────────────────────

export const broadcastSpaceEvent = onCall(
    { region: "us-central1" },
    async (request): Promise<{ eventId: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<BroadcastSpaceEventInput>;
        const spaceId = validateSpaceId(data.spaceId);

        if (typeof data.title !== "string" || !data.title.trim()) {
            throw new HttpsError("invalid-argument", "title is required.");
        }

        const db = getFirestore();
        await assertSpaceHost(db, spaceId, uid);

        const now = Timestamp.now();
        const { spaceId: _removed, ...eventFields } = data;

        const eventRef = db.collection(`spaces/${spaceId}/events`).doc();
        await eventRef.set({
            ...eventFields,
            createdBy: uid,
            createdAt: now,
            updatedAt: now,
            status: "scheduled",
        });

        return { eventId: eventRef.id };
    }
);

// ── broadcastSpaceAnnouncement ────────────────────────────────────────────────

export const broadcastSpaceAnnouncement = onCall(
    { region: "us-central1" },
    async (request): Promise<{ announcementId: string; memberCount: number }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data =
            (request.data ?? {}) as Partial<BroadcastSpaceAnnouncementInput>;
        const spaceId = validateSpaceId(data.spaceId);

        if (typeof data.message !== "string" || !data.message.trim()) {
            throw new HttpsError("invalid-argument", "message is required.");
        }

        const validScopes = ["all", "tier", "selected"];
        if (!data.scope || !validScopes.includes(data.scope)) {
            throw new HttpsError(
                "invalid-argument",
                `scope must be one of: ${validScopes.join(", ")}.`
            );
        }

        const validPriorities = ["normal", "high", "urgent"];
        if (!data.priority || !validPriorities.includes(data.priority)) {
            throw new HttpsError(
                "invalid-argument",
                `priority must be one of: ${validPriorities.join(", ")}.`
            );
        }

        const db = getFirestore();

        // Assert host ownership and fetch member list for count
        const [, membersSnap] = await Promise.all([
            assertSpaceHost(db, spaceId, uid),
            db.collection(`spaces/${spaceId}/members`).get(),
        ]);

        const memberCount = membersSnap.size;
        const memberIds: string[] = membersSnap.docs.map((d) => d.id);

        const now = Timestamp.now();
        const announcementRef = db.collection(`spaces/${spaceId}/announcements`).doc();

        await announcementRef.set({
            message: data.message.trim(),
            scope: data.scope,
            priority: data.priority,
            scheduledAt: data.scheduledAt ?? null,
            eventId: data.eventId ?? null,
            memberIds,
            createdAt: now,
            createdBy: uid,
        });

        return { announcementId: announcementRef.id, memberCount };
    }
);
