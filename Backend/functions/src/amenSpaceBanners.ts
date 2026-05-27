import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

const allowedTypes = new Set(["group", "job", "event", "discussion", "prayer", "sermon", "school", "business", "announcement"]);
const allowedSizes = new Set(["compact", "standard", "large", "hero"]);
const allowedSurfaces = new Set([
    "spacesHome",
    "spaceDetail",
    "churchProfile",
    "schoolProfile",
    "businessProfile",
    "discovery",
    "events",
    "jobs",
    "messagesRooms",
    "bereanSuggestions",
    "homeFeed",
]);
const allowedCtas = new Set(["Join", "RSVP", "Apply", "Open", "Pray", "Watch"]);
const allowedEvents = new Set(["banner_impression", "banner_tap", "banner_dismiss", "banner_cta_complete", "banner_hidden_reason"]);

type BannerVisibility = "public" | "authenticated" | "spaceMembers" | "organizationMembers" | "private";

export interface AmenSpaceBannerRecord {
    id: string;
    type: string;
    title: string;
    subtitle: string;
    imageURL?: string;
    iconURL?: string;
    spaceId?: string;
    organizationId?: string;
    surfaces: string[];
    targetRoute: string;
    ctaLabel: string;
    priority: number;
    startsAt?: FirebaseFirestore.Timestamp;
    endsAt?: FirebaseFirestore.Timestamp;
    location?: string;
    moderationStatus: string;
    visibility: BannerVisibility;
    createdBy?: string;
    trustedContext?: string;
    rankingReason?: string;
    safetyScore?: number;
    urgencyScore?: number;
    relevanceScore?: number;
    localScore?: number;
    trustedParticipationScore?: number;
    originalityScore?: number;
    usefulnessScore?: number;
}

interface BannerViewerContext {
    uid: string;
    spaceIds: Set<string>;
    organizationIds: Set<string>;
    dismissedBannerIds: Set<string>;
}

function requireAuth(request: { auth?: { uid: string; token?: Record<string, unknown> } | null }) {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
    return request.auth.uid;
}

function str(data: Record<string, unknown>, key: string, fallback = "") {
    const value = data[key];
    return typeof value === "string" ? value.trim() : fallback;
}

function num(data: Record<string, unknown>, key: string, fallback = 0) {
    const value = data[key];
    return typeof value === "number" ? value : fallback;
}

function strings(data: Record<string, unknown>, key: string) {
    const value = data[key];
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function timestamp(data: Record<string, unknown>, key: string) {
    const value = data[key];
    return value instanceof admin.firestore.Timestamp ? value : undefined;
}

function assertAllowed(value: string, allowed: Set<string>, field: string) {
    if (!allowed.has(value)) throw new HttpsError("invalid-argument", `Unsupported ${field}.`);
    return value;
}

function parseBanner(doc: FirebaseFirestore.QueryDocumentSnapshot): AmenSpaceBannerRecord | null {
    const data = doc.data();
    const title = str(data, "title");
    const targetRoute = str(data, "targetRoute");
    const ctaLabel = str(data, "ctaLabel", "Open");
    const type = str(data, "type", "announcement");
    if (!title || !targetRoute || !allowedCtas.has(ctaLabel) || !allowedTypes.has(type)) return null;
    return {
        id: doc.id,
        type,
        title,
        subtitle: str(data, "subtitle"),
        imageURL: str(data, "imageURL") || undefined,
        iconURL: str(data, "iconURL") || undefined,
        spaceId: str(data, "spaceId") || undefined,
        organizationId: str(data, "organizationId") || undefined,
        surfaces: strings(data, "surfaces"),
        targetRoute,
        ctaLabel,
        priority: num(data, "priority"),
        startsAt: timestamp(data, "startsAt"),
        endsAt: timestamp(data, "endsAt"),
        location: str(data, "location") || undefined,
        moderationStatus: str(data, "moderationStatus", "pending"),
        visibility: str(data, "visibility", "authenticated") as BannerVisibility,
        createdBy: str(data, "createdBy") || undefined,
        trustedContext: str(data, "trustedContext") || undefined,
        rankingReason: str(data, "rankingReason") || undefined,
        safetyScore: num(data, "safetyScore", 1),
        urgencyScore: num(data, "urgencyScore"),
        relevanceScore: num(data, "relevanceScore"),
        localScore: num(data, "localScore"),
        trustedParticipationScore: num(data, "trustedParticipationScore"),
        originalityScore: num(data, "originalityScore"),
        usefulnessScore: num(data, "usefulnessScore"),
    };
}

export function isAmenSpaceBannerEligible(
    banner: AmenSpaceBannerRecord,
    viewer: BannerViewerContext,
    surface: string,
    referenceDate = new Date()
): boolean {
    if (!allowedSurfaces.has(surface)) return false;
    if (!["approved", "visible"].includes(banner.moderationStatus)) return false;
    if (!banner.surfaces.includes(surface)) return false;
    if (viewer.dismissedBannerIds.has(banner.id)) return false;
    if (banner.startsAt && banner.startsAt.toDate() > referenceDate) return false;
    if (banner.endsAt && banner.endsAt.toDate() < referenceDate) return false;
    if (banner.visibility === "private") return false;
    if (banner.visibility === "spaceMembers" && (!banner.spaceId || !viewer.spaceIds.has(banner.spaceId))) return false;
    if (banner.visibility === "organizationMembers" && (!banner.organizationId || !viewer.organizationIds.has(banner.organizationId))) return false;
    return true;
}

export function rankAmenSpaceBanners(banners: AmenSpaceBannerRecord[]): AmenSpaceBannerRecord[] {
    return [...banners].sort((lhs, rhs) => bannerScore(rhs) - bannerScore(lhs));
}

export function resolveAmenSpaceBannerSize(userPreference?: string, adminDefault?: string, surfaceDefault = "standard") {
    if (userPreference && allowedSizes.has(userPreference)) return userPreference;
    if (adminDefault && allowedSizes.has(adminDefault)) return adminDefault;
    if (allowedSizes.has(surfaceDefault)) return surfaceDefault;
    return "standard";
}

export function dedupeAmenSpaceBanners(banners: AmenSpaceBannerRecord[]) {
    const seenRoutes = new Set<string>();
    return banners.filter((banner) => {
        if (seenRoutes.has(banner.targetRoute)) return false;
        seenRoutes.add(banner.targetRoute);
        return true;
    });
}

function bannerScore(banner: AmenSpaceBannerRecord) {
    return banner.priority +
        (banner.urgencyScore ?? 0) * 1.5 +
        (banner.relevanceScore ?? 0) * 2 +
        (banner.localScore ?? 0) +
        (banner.trustedParticipationScore ?? 0) * 1.4 +
        (banner.safetyScore ?? 0) * 2 +
        (banner.originalityScore ?? 0) * 0.6 +
        (banner.usefulnessScore ?? 0) * 1.6;
}

async function loadViewerContext(uid: string): Promise<BannerViewerContext> {
    const [spaceMemberships, organizationMemberships, dismissals] = await Promise.all([
        db.collectionGroup("members").where("userId", "==", uid).limit(100).get(),
        db.collectionGroup("organizationMembers").where("userId", "==", uid).limit(100).get(),
        db.collection("users").doc(uid).collection("dismissedSpaceBanners").limit(200).get(),
    ]);
    return {
        uid,
        spaceIds: new Set(spaceMemberships.docs.map((doc) => String(doc.ref.parent.parent?.id ?? "")).filter(Boolean)),
        organizationIds: new Set(organizationMemberships.docs.map((doc) => String(doc.ref.parent.parent?.id ?? "")).filter(Boolean)),
        dismissedBannerIds: new Set(dismissals.docs.map((doc) => doc.id)),
    };
}

async function loadSizeDefaults(uid: string, surface: string, spaceId?: string) {
    const [userPref, spaceDefault] = await Promise.all([
        db.collection("users").doc(uid).collection("bannerDisplayPreferences").doc(surface).get(),
        spaceId ? db.collection("amenSpaces").doc(spaceId).collection("settings").doc("bannerDisplay").get() : Promise.resolve(null),
    ]);
    return {
        userPreference: str(userPref.data() ?? {}, "bannerSize") || undefined,
        adminDefault: str(spaceDefault?.data() ?? {}, "defaultBannerSize") || undefined,
    };
}

function payloadForBanner(banner: AmenSpaceBannerRecord, resolvedSize: string) {
    return {
        id: banner.id,
        type: banner.type,
        title: banner.title,
        subtitle: banner.subtitle,
        imageURL: banner.imageURL ?? null,
        iconURL: banner.iconURL ?? null,
        spaceId: banner.spaceId ?? null,
        targetRoute: banner.targetRoute,
        ctaLabel: banner.ctaLabel,
        priority: banner.priority,
        startsAt: banner.startsAt?.toMillis() ? banner.startsAt.toMillis() / 1000 : null,
        endsAt: banner.endsAt?.toMillis() ? banner.endsAt.toMillis() / 1000 : null,
        location: banner.location ?? null,
        moderationStatus: banner.moderationStatus,
        visibility: banner.visibility,
        createdBy: banner.createdBy ?? null,
        trustedContext: banner.trustedContext ?? null,
        rankingReason: banner.rankingReason || "Relevant to your Amen Spaces activity",
        resolvedSize,
    };
}

export const getAmenSpaceBanners = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const surface = assertAllowed(str(data, "surface"), allowedSurfaces, "surface");
    const spaceId = str(data, "spaceId") || undefined;
    const surfaceDefaultSize = str(data, "surfaceDefaultSize", "standard");
    const [viewer, sizeDefaults, bannerSnap] = await Promise.all([
        loadViewerContext(uid),
        loadSizeDefaults(uid, surface, spaceId),
        db.collection("amenSpaceBanners").where("surfaces", "array-contains", surface).limit(50).get(),
    ]);
    const resolvedSize = resolveAmenSpaceBannerSize(sizeDefaults.userPreference, sizeDefaults.adminDefault, surfaceDefaultSize);
    const eligible = bannerSnap.docs
        .map(parseBanner)
        .filter((banner): banner is AmenSpaceBannerRecord => !!banner)
        .filter((banner) => isAmenSpaceBannerEligible(banner, viewer, surface));
    const items = dedupeAmenSpaceBanners(rankAmenSpaceBanners(eligible)).slice(0, 12).map((banner) => payloadForBanner(banner, resolvedSize));
    return { ok: true, resolvedSize, items };
});

export const setAmenSpaceBannerDisplayPreference = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const surface = assertAllowed(str(data, "surface"), allowedSurfaces, "surface");
    const bannerSize = assertAllowed(str(data, "bannerSize"), allowedSizes, "bannerSize");
    await db.collection("users").doc(uid).collection("bannerDisplayPreferences").doc(surface).set({
        uid,
        surface,
        bannerSize,
        updatedAt: now(),
    }, { merge: true });
    return { ok: true, bannerSize };
});

export const setAmenSpaceDefaultBannerSize = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const spaceId = str(data, "spaceId");
    const defaultBannerSize = assertAllowed(str(data, "defaultBannerSize"), allowedSizes, "defaultBannerSize");
    if (!spaceId) throw new HttpsError("invalid-argument", "Missing spaceId.");
    const member = await db.collection("amenSpaces").doc(spaceId).collection("members").doc(uid).get();
    const role = str(member.data() ?? {}, "role");
    if (!["owner", "admin", "moderator"].includes(role)) throw new HttpsError("permission-denied", "Only space admins can set the default banner size.");
    await db.collection("amenSpaces").doc(spaceId).collection("settings").doc("bannerDisplay").set({
        defaultBannerSize,
        updatedBy: uid,
        updatedAt: now(),
    }, { merge: true });
    return { ok: true, defaultBannerSize };
});

export const logAmenSpaceBannerEvent = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const bannerId = str(data, "bannerId");
    const surface = assertAllowed(str(data, "surface"), allowedSurfaces, "surface");
    const eventName = assertAllowed(str(data, "eventName"), allowedEvents, "eventName");
    if (!bannerId) throw new HttpsError("invalid-argument", "Missing bannerId.");
    await db.collection("amenSpaceBannerAnalytics").add({
        uid,
        bannerId,
        surface,
        eventName,
        createdAt: now(),
    });
    if (eventName === "banner_dismiss") {
        await db.collection("users").doc(uid).collection("dismissedSpaceBanners").doc(bannerId).set({
            bannerId,
            surface,
            dismissedAt: now(),
        }, { merge: true });
    }
    return { ok: true };
});

export const validateAmenSpaceBannerCTA = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const bannerId = str(data, "bannerId");
    const surface = assertAllowed(str(data, "surface"), allowedSurfaces, "surface");
    const ctaLabel = assertAllowed(str(data, "ctaLabel"), allowedCtas, "ctaLabel");
    if (!bannerId) throw new HttpsError("invalid-argument", "Missing bannerId.");
    const snap = await db.collection("amenSpaceBanners").doc(bannerId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Banner not found.");
    const parsed = parseBanner(snap as FirebaseFirestore.QueryDocumentSnapshot);
    if (!parsed || parsed.ctaLabel !== ctaLabel) throw new HttpsError("failed-precondition", "CTA is no longer valid.");
    const viewer = await loadViewerContext(uid);
    if (!isAmenSpaceBannerEligible(parsed, viewer, surface)) throw new HttpsError("permission-denied", "Banner is no longer available.");
    await db.collection("amenSpaceBannerAnalytics").add({
        uid,
        bannerId,
        surface,
        eventName: "banner_tap",
        ctaLabel,
        createdAt: now(),
    });
    return { ok: true, targetRoute: parsed.targetRoute, ctaLabel };
});
