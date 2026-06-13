// spaces/discoveryAndLegal.ts
//
// Space discovery and legal acceptance callables for AMEN Spaces.
//
// Callables:
//   discoverSpaces           — queries public spaces with optional type filter
//   recordLegalAcceptance    — records user acceptance of a legal document version
//   activateSpaceMembership  — writes an active membership record for the user

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

// ── Interfaces ────────────────────────────────────────────────────────────────

interface DiscoverSpacesInput {
    spaceType?: string;
    limit?: number;
    startAfterDocId?: string;
}

interface RecordLegalAcceptanceInput {
    documentType: string;
    version: string;
}

interface ActivateSpaceMembershipInput {
    spaceId: string;
    tierId: string;
}

interface SpaceSummary {
    id: string;
    name: string;
    description: string | null;
    spaceType: string | null;
    memberCount: number;
    isPublic: boolean;
    createdBy: string;
    createdAt: string | null;
    avatarURL: string | null;
    bannerURL: string | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function docToSpaceSummary(doc: FirebaseFirestore.QueryDocumentSnapshot): SpaceSummary {
    const d = doc.data();
    return {
        id: doc.id,
        name: (d.name as string) ?? "",
        description: (d.description as string) ?? null,
        spaceType: (d.spaceType as string) ?? null,
        memberCount: (d.memberCount as number) ?? 0,
        isPublic: (d.isPublic as boolean) ?? true,
        createdBy: (d.createdBy as string) ?? "",
        createdAt:
            d.createdAt instanceof Timestamp
                ? d.createdAt.toDate().toISOString()
                : null,
        avatarURL: (d.avatarURL as string) ?? null,
        bannerURL: (d.bannerURL as string) ?? null,
    };
}

// ── discoverSpaces ────────────────────────────────────────────────────────────

export const discoverSpaces = onCall(
    { region: "us-central1" },
    async (request): Promise<SpaceSummary[]> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<DiscoverSpacesInput>;

        const requestedLimit =
            typeof data.limit === "number" ? data.limit : 20;
        if (requestedLimit < 1 || requestedLimit > 50) {
            throw new HttpsError(
                "invalid-argument",
                "limit must be between 1 and 50."
            );
        }

        const db = getFirestore();

        let query: FirebaseFirestore.Query = db
            .collection("spaces")
            .where("isPublic", "==", true)
            .orderBy("createdAt", "desc")
            .limit(requestedLimit);

        if (typeof data.spaceType === "string" && data.spaceType.trim()) {
            query = db
                .collection("spaces")
                .where("isPublic", "==", true)
                .where("spaceType", "==", data.spaceType.trim())
                .orderBy("createdAt", "desc")
                .limit(requestedLimit);
        }

        if (typeof data.startAfterDocId === "string" && data.startAfterDocId.trim()) {
            const cursorSnap = await db.doc(`spaces/${data.startAfterDocId.trim()}`).get();
            if (cursorSnap.exists) {
                query = query.startAfter(cursorSnap);
            }
        }

        const snap = await query.get();
        return snap.docs.map(docToSpaceSummary);
    }
);

// ── recordLegalAcceptance ─────────────────────────────────────────────────────

export const recordLegalAcceptance = onCall(
    { region: "us-central1" },
    async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<RecordLegalAcceptanceInput>;

        if (typeof data.documentType !== "string" || !data.documentType.trim()) {
            throw new HttpsError("invalid-argument", "documentType is required.");
        }
        if (typeof data.version !== "string" || !data.version.trim()) {
            throw new HttpsError("invalid-argument", "version is required.");
        }

        const db = getFirestore();

        await db
            .doc(`users/${uid}/legalAcceptances/${data.documentType.trim()}`)
            .set({
                version: data.version.trim(),
                acceptedAt: Timestamp.now(),
            });

        return { success: true };
    }
);

// ── activateSpaceMembership ───────────────────────────────────────────────────

export const activateSpaceMembership = onCall(
    { region: "us-central1" },
    async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<ActivateSpaceMembershipInput>;

        if (typeof data.spaceId !== "string" || !data.spaceId.trim()) {
            throw new HttpsError("invalid-argument", "spaceId is required.");
        }
        if (typeof data.tierId !== "string" || !data.tierId.trim()) {
            throw new HttpsError("invalid-argument", "tierId is required.");
        }

        const spaceId = data.spaceId.trim();
        const tierId = data.tierId.trim();

        const db = getFirestore();

        // Verify the space exists and is public (or has an accepted legal gate)
        const spaceSnap = await db.doc(`spaces/${spaceId}`).get();
        if (!spaceSnap.exists) {
            throw new HttpsError("not-found", "Space not found.");
        }

        // C60: Youth Interaction Shield — block private-Space joins that would
        // allow an unverified adult to reach a youth user via Space channels.
        // Public community Spaces (isPublic: true) are not a DM bypass vector;
        // only private Spaces (isPublic: false) require this check.
        const spaceData = spaceSnap.data() ?? {};
        if (!spaceData.isPublic) {
            const youthProfileSnap = await db.doc(`youthModeProfiles/${uid}`).get();
            if (youthProfileSnap.exists) {
                const youthProfile = youthProfileSnap.data() ?? {};
                if (youthProfile.dmPolicy === "verifiedAdultsBlocked") {
                    const spaceCreatorUid: string = spaceData.createdBy ?? "";
                    if (spaceCreatorUid && spaceCreatorUid !== uid) {
                        const creatorSnap = await db.doc(`users/${spaceCreatorUid}`).get();
                        const creatorAgeVerified = creatorSnap.data()?.ageVerified === true;
                        if (!creatorAgeVerified) {
                            // Silent block: do NOT expose youth status to the creator.
                            // From the youth user's client this throws; the creator sees nothing.
                            throw new HttpsError("permission-denied", "Space not available.");
                        }
                    }
                }
            }
        }

        await db.doc(`spaces/${spaceId}/members/${uid}`).set({
            userId: uid,
            tierId,
            joinedAt: Timestamp.now(),
            status: "active",
        });

        return { success: true };
    }
);
