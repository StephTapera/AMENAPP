import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

type SourceType = "church" | "college" | "university" | "nonprofit" | "organization" | "personal" | "marketplace" | "mentor" | "creator";
type Visibility = "publicOpen" | "publicToSpace" | "organizationOnly" | "privateRestricted" | "privateGroup" | "paidMemberOnly" | "paidTier" | "youthProtected" | "confidential" | "readOnlyPublic";
type JoinPolicy = "open" | "requestRequired" | "inviteOnly" | "paidOnly" | "roleRestricted" | "readOnly";
type MembershipStatus = "notJoined" | "requested" | "joined" | "blocked" | "unavailable";
type SafetyStatus = "allowed" | "allowWithWarning" | "allow_with_warning" | "needsReview" | "needs_review" | "blocked" | "escalated" | "pending";
type ModerationStatus = "visible" | "approved" | "underReview" | "under_review" | "hidden" | "deleted" | "pending";
type ActionKind = "join" | "request" | "leave" | "report" | "save" | "mute" | "interested" | "generateDiscovery" | "moderatePreview";

interface ViewerContext {
    uid: string;
    isSpaceMember: boolean;
    isOrganizationMember: boolean;
    role: string | null;
    tierIds: Set<string>;
    canAccessYouthProtected: boolean;
    canViewConfidential: boolean;
}

interface DiscussionRecord {
    id: string;
    spaceId: string;
    organizationId?: string;
    sourceType: SourceType;
    title: string;
    subtitle: string;
    descriptionPreview: string;
    category: string;
    tags: string[];
    visibility: Visibility;
    joinPolicy: JoinPolicy;
    participantCount: number;
    unreadCount: number;
    trendingScore: number;
    safetyStatus: SafetyStatus;
    moderationStatus: ModerationStatus;
    trustBadges: string[];
    isLive: boolean;
    isVerified: boolean;
    isYouthProtected: boolean;
    isConfidential: boolean;
    requiresTier?: string;
    recommendationReason?: string;
    aiSummary?: string;
    isAIExcluded: boolean;
    approximateRegion?: string;
    lastActivityAt?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
    createdAt?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}

function requireAuth(request: { auth?: { uid: string; token?: Record<string, unknown> } | null }) {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
    return request.auth.uid;
}

function str(data: Record<string, unknown>, key: string, fallback = "") {
    const value = data[key];
    return typeof value === "string" ? value.trim() : fallback;
}

function bool(data: Record<string, unknown>, key: string, fallback = false) {
    const value = data[key];
    return typeof value === "boolean" ? value : fallback;
}

function num(data: Record<string, unknown>, key: string, fallback = 0) {
    const value = data[key];
    return typeof value === "number" ? value : fallback;
}

function strings(data: Record<string, unknown>, key: string) {
    const value = data[key];
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function normalizeSafety(value: string): SafetyStatus {
    if (value === "allow_with_warning") return "allowWithWarning";
    if (value === "needs_review") return "needsReview";
    return (value || "allowed") as SafetyStatus;
}

function normalizeModeration(value: string): ModerationStatus {
    if (value === "approved") return "visible";
    if (value === "under_review") return "underReview";
    return (value || "visible") as ModerationStatus;
}

function normalizeVisibility(value: string): Visibility {
    if (value === "publicToSpace") return "publicOpen";
    if (value === "paidTier") return "paidMemberOnly";
    if (value === "privateGroup") return "privateRestricted";
    return (value || "publicOpen") as Visibility;
}

function parseDiscussion(spaceId: string, discussionId: string, data: Record<string, unknown>): DiscussionRecord {
    return {
        id: discussionId,
        spaceId,
        organizationId: str(data, "organizationId") || undefined,
        sourceType: (str(data, "sourceType", "organization") as SourceType),
        title: str(data, "title", str(data, "name", "Amen Spaces discussion")),
        subtitle: str(data, "subtitle", str(data, "sourceName", "Amen Space")),
        descriptionPreview: str(data, "descriptionPreview", str(data, "description")),
        category: str(data, "category", "All"),
        tags: strings(data, "tags"),
        visibility: normalizeVisibility(str(data, "visibility", "publicOpen")),
        joinPolicy: (str(data, "joinPolicy", "open") as JoinPolicy),
        participantCount: num(data, "participantCount", num(data, "memberCount")),
        unreadCount: num(data, "unreadCount"),
        trendingScore: num(data, "trendingScore", num(data, "weeklyActiveUsers")),
        safetyStatus: normalizeSafety(str(data, "safetyStatus", "allowed")),
        moderationStatus: normalizeModeration(str(data, "moderationStatus", "visible")),
        trustBadges: strings(data, "trustBadges"),
        isLive: bool(data, "isLive"),
        isVerified: bool(data, "isVerified"),
        isYouthProtected: bool(data, "isYouthProtected") || str(data, "visibility") === "youthProtected",
        isConfidential: bool(data, "isConfidential") || str(data, "visibility") === "confidential",
        requiresTier: str(data, "requiresTier", str(data, "requiredTierId")) || undefined,
        recommendationReason: str(data, "recommendationReason") || undefined,
        aiSummary: str(data, "aiSummary") || undefined,
        isAIExcluded: bool(data, "isAIExcluded", bool(data, "aiExcluded")),
        approximateRegion: str(data, "approximateRegion") || undefined,
        lastActivityAt: (data.lastActivityAt as FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue | undefined),
        createdAt: (data.createdAt as FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue | undefined),
    };
}

export function canSurfaceDiscussion(discussion: DiscussionRecord, viewer: ViewerContext): boolean {
    const moderation = normalizeModeration(String(discussion.moderationStatus));
    const safety = normalizeSafety(String(discussion.safetyStatus));
    if (["hidden", "deleted", "underReview", "pending"].includes(moderation)) return false;
    if (["blocked", "escalated", "needsReview", "pending"].includes(safety)) return false;
    if (discussion.isConfidential || discussion.visibility === "confidential") {
        return viewer.canViewConfidential || viewer.role === "owner" || viewer.role === "admin" || viewer.role === "moderator";
    }
    if (discussion.isYouthProtected || discussion.visibility === "youthProtected") {
        return viewer.canAccessYouthProtected;
    }
    if (discussion.visibility === "privateRestricted") {
        return viewer.isSpaceMember || viewer.isOrganizationMember;
    }
    if (discussion.visibility === "organizationOnly") {
        return viewer.isOrganizationMember || viewer.isSpaceMember;
    }
    return true;
}

export function resolveJoinAction(discussion: DiscussionRecord, viewer: ViewerContext, membershipStatus: MembershipStatus): "Join" | "Request" | "View" | "Joined" | "Live" | "Unavailable" {
    if (!canSurfaceDiscussion(discussion, viewer)) return "Unavailable";
    if (membershipStatus === "blocked" || membershipStatus === "unavailable") return "Unavailable";
    if (membershipStatus === "requested") return "Request";
    if (membershipStatus === "joined") return discussion.isLive ? "Live" : "Joined";
    if (discussion.joinPolicy === "readOnly" || discussion.visibility === "readOnlyPublic") return "View";
    if (discussion.joinPolicy === "inviteOnly") return "Unavailable";
    if (discussion.joinPolicy === "requestRequired" || discussion.joinPolicy === "roleRestricted") return "Request";
    if (discussion.joinPolicy === "paidOnly" || discussion.visibility === "paidMemberOnly") return "Join";
    return "Join";
}

export function safePreviewForDiscovery(discussion: DiscussionRecord, viewer: ViewerContext): string {
    if (!canSurfaceDiscussion(discussion, viewer)) return "Preview unavailable until access is approved.";
    if (discussion.isConfidential || discussion.visibility === "confidential") return "Confidential discussion. Preview hidden.";
    if ((discussion.visibility === "paidMemberOnly" || discussion.joinPolicy === "paidOnly") && discussion.requiresTier && !viewer.tierIds.has(discussion.requiresTier)) {
        return "Member-only discussion. Preview available after access is confirmed.";
    }
    if ((discussion.isYouthProtected || discussion.visibility === "youthProtected") && !viewer.canAccessYouthProtected) {
        return "Youth-protected discussion. Preview hidden.";
    }
    return discussion.aiSummary && !discussion.isAIExcluded ? discussion.aiSummary : discussion.descriptionPreview;
}

export function moderatePreviewText(text: string): { safetyStatus: SafetyStatus; moderationStatus: ModerationStatus; reasons: string[] } {
    const lower = text.toLowerCase();
    const reasons: string[] = [];
    if (/(secret meetup|do not tell|minor alone|send pics|explicit)/.test(lower)) reasons.push("youth_safety_risk");
    if (/(kill myself|suicide|self harm)/.test(lower)) reasons.push("crisis_language");
    if (/(hate|threat|doxx|harass)/.test(lower)) reasons.push("abuse_or_doxxing_risk");
    if (/(cashapp|venmo|wire transfer|telegram|whatsapp|off platform)/.test(lower)) reasons.push("off_platform_pressure");
    if (reasons.includes("crisis_language")) return { safetyStatus: "escalated", moderationStatus: "underReview", reasons };
    if (reasons.length > 0) return { safetyStatus: "needsReview", moderationStatus: "underReview", reasons };
    return { safetyStatus: "allowed", moderationStatus: "visible", reasons };
}

async function enforceAmenSpacesRateLimit(uid: string, action: ActionKind, maxPerMinute: number) {
    const ref = db.collection("_rateLimits").doc(`amenSpaces_${uid}_${action}`);
    const nowMs = Date.now();
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.data() ?? {};
        const windowStartedAt = Number(data.windowStartedAt ?? 0);
        const currentCount = nowMs - windowStartedAt > 60_000 ? 0 : Number(data.count ?? 0);
        if (currentCount >= maxPerMinute) {
            throw new HttpsError("resource-exhausted", "Please slow down and try again in a moment.");
        }
        tx.set(ref, {
            uid,
            action,
            windowStartedAt: currentCount === 0 ? nowMs : windowStartedAt,
            count: currentCount + 1,
            updatedAt: now(),
        }, { merge: true });
    });
}

async function loadViewerContext(uid: string, spaceId: string, organizationId?: string, token?: Record<string, unknown>): Promise<ViewerContext> {
    const [spaceMember, connectMember, organizationMember, tierSnap] = await Promise.all([
        db.collection("amenSpaces").doc(spaceId).collection("members").doc(uid).get(),
        db.collection("connectSpaces").doc(spaceId).collection("members").doc(uid).get(),
        organizationId ? db.collection("amenSpacesOrganizations").doc(organizationId).collection("members").doc(uid).get() : Promise.resolve(null),
        db.collection("amenSpacesEntitlements").doc(uid).collection("tiers").get(),
    ]);
    const memberData = spaceMember.exists ? spaceMember.data() : connectMember.data();
    const role = typeof memberData?.role === "string" ? memberData.role : null;
    const tokenRole = typeof token?.amenSpacesRole === "string" ? token.amenSpacesRole : null;
    const ageTier = typeof token?.ageTier === "string" ? token.ageTier : "";
    const tierIds = new Set<string>();
    tierSnap.docs.forEach((doc) => tierIds.add(doc.id));
    return {
        uid,
        isSpaceMember: spaceMember.exists || connectMember.exists,
        isOrganizationMember: !!organizationMember?.exists,
        role: role ?? tokenRole,
        tierIds,
        canAccessYouthProtected: ["owner", "admin", "moderator", "parentGuardian", "youth"].includes(role ?? tokenRole ?? "") || ageTier === "youth_verified",
        canViewConfidential: ["owner", "admin", "moderator"].includes(role ?? tokenRole ?? ""),
    };
}

async function loadDiscussion(spaceId: string, discussionId: string): Promise<{ discussion: DiscussionRecord; ref: FirebaseFirestore.DocumentReference }> {
    const primaryRef = db.collection("amenSpaces").doc(spaceId).collection("discussions").doc(discussionId);
    const primary = await primaryRef.get();
    if (primary.exists) return { discussion: parseDiscussion(spaceId, discussionId, primary.data() ?? {}), ref: primaryRef };

    const connectRef = db.collection("connectSpaces").doc(spaceId).collection("channels").doc(discussionId);
    const connect = await connectRef.get();
    if (connect.exists) return { discussion: parseDiscussion(spaceId, discussionId, connect.data() ?? {}), ref: connectRef };

    throw new HttpsError("not-found", "Discussion not found.");
}

async function membershipStatus(uid: string, discussion: DiscussionRecord): Promise<MembershipStatus> {
    const memberId = `${discussion.id}_${uid}`;
    const [primary, connect] = await Promise.all([
        db.collection("amenSpaces").doc(discussion.spaceId).collection("discussionMembers").doc(memberId).get(),
        db.collection("connectSpaces").doc(discussion.spaceId).collection("discussionMembers").doc(memberId).get(),
    ]);
    const data = primary.exists ? primary.data() : connect.data();
    if (!data) return "notJoined";
    return (str(data, "status", "joined") as MembershipStatus);
}

function safeDiscoveryPayload(discussion: DiscussionRecord, viewer: ViewerContext, status: MembershipStatus) {
    const preview = safePreviewForDiscovery(discussion, viewer);
    const canUseAI = !discussion.isAIExcluded && !discussion.isConfidential && discussion.visibility !== "confidential" && canSurfaceDiscussion(discussion, viewer);
    return {
        id: discussion.id,
        spaceId: discussion.spaceId,
        organizationId: discussion.organizationId ?? null,
        sourceType: discussion.sourceType,
        title: discussion.title,
        subtitle: discussion.subtitle,
        descriptionPreview: preview,
        category: discussion.category,
        tags: discussion.tags,
        visibility: discussion.visibility,
        joinPolicy: discussion.joinPolicy,
        membershipStatus: status,
        participantCount: discussion.participantCount,
        unreadCount: discussion.unreadCount,
        trendingScore: discussion.trendingScore,
        safetyStatus: normalizeSafety(String(discussion.safetyStatus)),
        moderationStatus: normalizeModeration(String(discussion.moderationStatus)),
        trustBadges: discussion.trustBadges,
        isLive: discussion.isLive,
        isVerified: discussion.isVerified,
        isYouthProtected: discussion.isYouthProtected,
        isConfidential: discussion.isConfidential,
        requiresTier: discussion.requiresTier ?? null,
        recommendationReason: canUseAI ? discussion.recommendationReason ?? null : null,
        aiSummary: canUseAI ? discussion.aiSummary ?? null : null,
        accessAction: resolveJoinAction(discussion, viewer, status),
        approximateRegion: discussion.approximateRegion ?? null,
        lastActivityAt: discussion.lastActivityAt ?? now(),
        createdAt: discussion.createdAt ?? now(),
        indexedAt: now(),
    };
}

async function requireJoinable(uid: string, discussion: DiscussionRecord, viewer: ViewerContext, status: MembershipStatus) {
    if (!canSurfaceDiscussion(discussion, viewer)) throw new HttpsError("permission-denied", "You do not have access to that discussion.");
    if (["blocked", "unavailable"].includes(status)) throw new HttpsError("permission-denied", "You cannot join that discussion.");
    if (discussion.joinPolicy === "inviteOnly") throw new HttpsError("permission-denied", "This discussion requires an invite.");
    if ((discussion.joinPolicy === "paidOnly" || discussion.visibility === "paidMemberOnly") && discussion.requiresTier && !viewer.tierIds.has(discussion.requiresTier)) {
        throw new HttpsError("failed-precondition", "This discussion requires member access.");
    }
    if (discussion.joinPolicy === "roleRestricted" && !viewer.isOrganizationMember && !viewer.isSpaceMember) {
        throw new HttpsError("permission-denied", "This discussion is restricted to organization members.");
    }
    return uid;
}

async function writeDiscussionAudit(uid: string, discussion: DiscussionRecord, action: ActionKind, metadata: Record<string, unknown> = {}) {
    await db.collection("amenSpaces").doc(discussion.spaceId).collection("auditLogs").add({
        actorId: uid,
        action,
        targetType: "discussion",
        targetId: discussion.id,
        metadata,
        createdAt: now(),
    });
}

export const generateAmenSpacesDiscovery = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "generateDiscovery", 20);

    const spacesSnap = await db.collection("amenSpaces").where("isDiscoverable", "==", true).limit(20).get();
    const items: Record<string, unknown>[] = [];
    const batch = db.batch();

    for (const spaceDoc of spacesSnap.docs) {
        const discussionsSnap = await spaceDoc.ref.collection("discussions").orderBy("lastActivityAt", "desc").limit(8).get();
        for (const discussionDoc of discussionsSnap.docs) {
            const discussion = parseDiscussion(spaceDoc.id, discussionDoc.id, discussionDoc.data());
            const viewer = await loadViewerContext(uid, discussion.spaceId, discussion.organizationId, request.auth?.token);
            const status = await membershipStatus(uid, discussion);
            if (!canSurfaceDiscussion(discussion, viewer)) continue;
            const payload = safeDiscoveryPayload(discussion, viewer, status);
            items.push(payload);
            batch.set(db.collection("amenSpacesDiscovery").doc(uid).collection("items").doc(discussion.id), payload, { merge: true });
        }
    }

    await batch.commit();
    return { ok: true, count: items.length, items: items.slice(0, 50) };
});

export const joinAmenSpaceDiscussion = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "join", 20);
    const data = request.data as Record<string, unknown>;
    const { discussion } = await loadDiscussion(str(data, "spaceId"), str(data, "discussionId"));
    const viewer = await loadViewerContext(uid, discussion.spaceId, discussion.organizationId, request.auth?.token);
    const status = await membershipStatus(uid, discussion);
    await requireJoinable(uid, discussion, viewer, status);
    if (discussion.joinPolicy === "requestRequired" || discussion.joinPolicy === "roleRestricted") {
        throw new HttpsError("failed-precondition", "Request access to join this discussion.");
    }
    const memberId = `${discussion.id}_${uid}`;
    const batch = db.batch();
    batch.set(db.collection("amenSpaces").doc(discussion.spaceId).collection("discussionMembers").doc(memberId), { userId: uid, discussionId: discussion.id, spaceId: discussion.spaceId, status: "joined", joinedAt: now(), updatedAt: now() }, { merge: true });
    batch.set(db.collection("amenSpacesDiscovery").doc(uid).collection("items").doc(discussion.id), { membershipStatus: "joined", updatedAt: now() }, { merge: true });
    batch.update(db.collection("amenSpaces").doc(discussion.spaceId).collection("discussions").doc(discussion.id), { participantCount: admin.firestore.FieldValue.increment(1), updatedAt: now() });
    await batch.commit();
    await writeDiscussionAudit(uid, discussion, "join");
    return { ok: true, membershipStatus: "joined" };
});

export const requestAmenSpaceDiscussionAccess = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "request", 10);
    const data = request.data as Record<string, unknown>;
    const { discussion } = await loadDiscussion(str(data, "spaceId"), str(data, "discussionId"));
    const viewer = await loadViewerContext(uid, discussion.spaceId, discussion.organizationId, request.auth?.token);
    const status = await membershipStatus(uid, discussion);
    if (!canSurfaceDiscussion(discussion, viewer) && discussion.visibility !== "privateRestricted") {
        throw new HttpsError("permission-denied", "You do not have access to request that discussion.");
    }
    if (status === "blocked") throw new HttpsError("permission-denied", "You cannot request that discussion.");
    await db.collection("amenSpaces").doc(discussion.spaceId).collection("discussionAccessRequests").doc(`${discussion.id}_${uid}`).set({
        userId: uid,
        discussionId: discussion.id,
        spaceId: discussion.spaceId,
        status: "pending",
        createdAt: now(),
        updatedAt: now(),
    }, { merge: true });
    await db.collection("amenSpacesDiscovery").doc(uid).collection("items").doc(discussion.id).set({ membershipStatus: "requested", updatedAt: now() }, { merge: true });
    await writeDiscussionAudit(uid, discussion, "request");
    return { ok: true, membershipStatus: "requested" };
});

export const leaveAmenSpaceDiscussion = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "leave", 30);
    const data = request.data as Record<string, unknown>;
    const { discussion } = await loadDiscussion(str(data, "spaceId"), str(data, "discussionId"));
    await db.collection("amenSpaces").doc(discussion.spaceId).collection("discussionMembers").doc(`${discussion.id}_${uid}`).set({ status: "notJoined", leftAt: now(), updatedAt: now() }, { merge: true });
    await db.collection("amenSpacesDiscovery").doc(uid).collection("items").doc(discussion.id).set({ membershipStatus: "notJoined", updatedAt: now() }, { merge: true });
    await writeDiscussionAudit(uid, discussion, "leave");
    return { ok: true, membershipStatus: "notJoined" };
});

export const reportAmenSpaceDiscussion = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "report", 8);
    const data = request.data as Record<string, unknown>;
    const { discussion } = await loadDiscussion(str(data, "spaceId"), str(data, "discussionId"));
    const reason = str(data, "reason", "safety_review").slice(0, 120);
    const reportRef = db.collection("amenSpacesReports").doc();
    await reportRef.set({
        reporterId: uid,
        discussionId: discussion.id,
        spaceId: discussion.spaceId,
        organizationId: discussion.organizationId ?? null,
        reason,
        status: "pending",
        createdAt: now(),
        updatedAt: now(),
    });
    await db.collection("amenSpacesDiscovery").doc(uid).collection("items").doc(discussion.id).set({ isReportedByViewer: true, updatedAt: now() }, { merge: true });
    await writeDiscussionAudit(uid, discussion, "report", { reportId: reportRef.id });
    return { ok: true, reportId: reportRef.id };
});

export const saveAmenSpaceDiscussion = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "save", 30);
    const data = request.data as Record<string, unknown>;
    const { discussion } = await loadDiscussion(str(data, "spaceId"), str(data, "discussionId"));
    await db.collection("amenSpacesSaved").doc(uid).collection("items").doc(discussion.id).set({ discussionId: discussion.id, spaceId: discussion.spaceId, savedAt: now() }, { merge: true });
    return { ok: true };
});

export const muteAmenSpaceDiscussion = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "mute", 30);
    const data = request.data as Record<string, unknown>;
    const { discussion } = await loadDiscussion(str(data, "spaceId"), str(data, "discussionId"));
    await db.collection("amenSpacesMuted").doc(uid).collection("items").doc(discussion.id).set({ discussionId: discussion.id, spaceId: discussion.spaceId, mutedAt: now() }, { merge: true });
    await db.collection("amenSpacesDiscovery").doc(uid).collection("items").doc(discussion.id).delete();
    return { ok: true };
});

export const rankAmenSpacesDiscussions = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "interested", 60);
    const data = request.data as Record<string, unknown>;
    const discussionId = str(data, "discussionId");
    const spaceId = str(data, "spaceId");
    await db.collection("amenSpacesDiscoverySignals").doc(uid).collection("items").doc(`${spaceId}_${discussionId}`).set({
        uid,
        spaceId,
        discussionId,
        signal: str(data, "intent", "interested"),
        createdAt: now(),
    }, { merge: true });
    return { ok: true };
});

export const moderateAmenSpacesDiscussionPreview = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceAmenSpacesRateLimit(uid, "moderatePreview", 30);
    const data = request.data as Record<string, unknown>;
    const moderation = moderatePreviewText(str(data, "descriptionPreview", str(data, "text")));
    if (moderation.moderationStatus !== "visible") {
        return { ok: true, safeToPreview: false, ...moderation, preview: "Preview unavailable while this discussion is reviewed." };
    }
    return { ok: true, safeToPreview: true, ...moderation, preview: str(data, "descriptionPreview", str(data, "text")).slice(0, 240) };
});
