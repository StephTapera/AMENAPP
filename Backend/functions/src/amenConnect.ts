import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import StripeConstructor from "stripe";

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

type ConnectRole = "owner" | "admin" | "moderator" | "leader" | "mentor" | "creator" | "teacher" | "member" | "paidMember" | "guest" | "youth" | "parentGuardian" | "readOnly";
type SafetyStatus = "pending" | "allowed" | "allow_with_warning" | "needs_review" | "blocked" | "escalated";
type ConnectPaymentKind = "tier" | "product" | "liveSession" | "booking" | string;
type ConnectStripeClient = Pick<InstanceType<typeof StripeConstructor>, "subscriptions">;
type ConnectStripeMetadata = Record<string, string>;
type ConnectStripeSession = {
    id: string;
    mode?: string | null;
    subscription?: string | null;
    customer?: string | null;
    metadata?: ConnectStripeMetadata | null;
};
type ConnectStripeSubscription = {
    id: string;
    status?: string;
    customer?: string | { id: string } | null;
    metadata?: ConnectStripeMetadata | null;
};
type ConnectStripeEvent = {
    type: string;
    data: { object: unknown };
};

const adminRoles: ConnectRole[] = ["owner", "admin"];
const moderatorRoles: ConnectRole[] = ["owner", "admin", "moderator"];
const leaderRoles: ConnectRole[] = ["owner", "admin", "moderator", "leader", "mentor", "creator", "teacher"];
const publicMarketplaceCategories = ["Jobs", "Babysitting", "Tutoring", "Services", "Rides", "Housing", "Volunteering", "Mentorship", "Items", "Local Help", "Digital Products", "Paid Events", "Bookings"];

function requireAuth(request: { auth?: { uid: string } | null }) {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
    return request.auth.uid;
}

function str(data: Record<string, unknown>, key: string, fallback = "") {
    const value = data[key];
    return typeof value === "string" ? value.trim() : fallback;
}

async function memberRole(spaceId: string, uid: string): Promise<ConnectRole | null> {
    const snap = await db.collection("connectSpaces").doc(spaceId).collection("members").doc(uid).get();
    if (!snap.exists) return null;
    return (snap.data()?.role ?? null) as ConnectRole | null;
}

async function requireSpaceRole(spaceId: string, uid: string, allowed: ConnectRole[]) {
    const role = await memberRole(spaceId, uid);
    if (!role || !allowed.includes(role)) {
        throw new HttpsError("permission-denied", "Insufficient Amen Connect permissions");
    }
    return role;
}

function moderationStatusForText(text: string): { status: SafetyStatus; reasons: string[] } {
    const lower = text.toLowerCase();
    const reasons: string[] = [];
    if (/(guaranteed|10x|risk-free|god guarantees|breakthrough for \$|cashapp|venmo|wire transfer|off platform|text me privately)/.test(lower)) reasons.push("monetization_or_off_platform_pressure");
    if (/(minor alone|secret meetup|do not tell|send pics|explicit)/.test(lower)) reasons.push("youth_or_grooming_risk");
    if (/(kill myself|suicide|self harm)/.test(lower)) reasons.push("crisis_language");
    if (/(hate|threat|doxx)/.test(lower)) reasons.push("abuse_or_doxxing_risk");
    if (reasons.includes("crisis_language")) return { status: "escalated", reasons };
    if (reasons.length > 0) return { status: "needs_review", reasons };
    return { status: "allowed", reasons };
}

async function writeAudit(spaceId: string, actorId: string, action: string, targetType: string, targetId: string, metadata: Record<string, unknown> = {}) {
    await db.collection("connectSpaces").doc(spaceId).collection("auditLogs").add({
        actorId,
        action,
        targetType,
        targetId,
        metadata,
        createdAt: now(),
    });
}

export const createConnectSpace = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const name = str(data, "name");
    if (!name || name.length > 100) throw new HttpsError("invalid-argument", "Space name is required");

    const spaceRef = db.collection("connectSpaces").doc();
    const payload = {
        name,
        type: str(data, "type", "Personal Group"),
        description: str(data, "description"),
        ownerId: uid,
        visibility: str(data, "visibility", "publicToSpace"),
        safetyMode: str(data, "safetyMode", "standard"),
        aiEnabled: data.aiEnabled !== false,
        aiExclusions: Array.isArray(data.aiExclusions) ? data.aiExclusions : [],
        memberCount: 1,
        dashboardTemplateId: str(data, "dashboardTemplateId", "community-dashboard"),
        moderationStatus: "allowed",
        safetyStatus: "allowed",
        createdAt: now(),
        updatedAt: now(),
        createdBy: uid,
    };

    const batch = db.batch();
    batch.set(spaceRef, payload);
    batch.set(spaceRef.collection("members").doc(uid), { role: "owner", status: "active", joinedAt: now(), permissions: ["*"] });
    batch.set(spaceRef.collection("channels").doc("announcements"), { name: "announcements", type: "announcement", visibility: "publicToSpace", allowedRoles: leaderRoles, aiSummaryEnabled: true, createdAt: now(), createdBy: uid });
    batch.set(spaceRef.collection("channels").doc("general"), { name: "general", type: "public", visibility: "publicToSpace", allowedRoles: ["owner", "admin", "moderator", "leader", "member", "paidMember"], aiSummaryEnabled: true, createdAt: now(), createdBy: uid });
    await batch.commit();
    await writeAudit(spaceRef.id, uid, "createConnectSpace", "space", spaceRef.id);
    return { ok: true, spaceId: spaceRef.id };
});

export const inviteConnectMember = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const spaceId = str(data, "spaceId");
    await requireSpaceRole(spaceId, uid, leaderRoles);
    const inviteRef = db.collection("connectSpaces").doc(spaceId).collection("invites").doc();
    await inviteRef.set({ email: str(data, "email"), role: str(data, "role", "member"), status: "pending", createdBy: uid, createdAt: now(), updatedAt: now() });
    await writeAudit(spaceId, uid, "inviteConnectMember", "invite", inviteRef.id);
    return { ok: true, inviteId: inviteRef.id };
});

export const acceptConnectInvite = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const spaceId = str(data, "spaceId");
    const inviteId = str(data, "inviteId");
    const inviteRef = db.collection("connectSpaces").doc(spaceId).collection("invites").doc(inviteId);
    const invite = await inviteRef.get();
    if (!invite.exists || invite.data()?.status !== "pending") throw new HttpsError("failed-precondition", "Invite is not available");
    await db.runTransaction(async (tx) => {
        tx.set(db.collection("connectSpaces").doc(spaceId).collection("members").doc(uid), { role: invite.data()?.role ?? "member", status: "active", joinedAt: now(), permissions: [] }, { merge: true });
        tx.update(inviteRef, { status: "accepted", acceptedBy: uid, updatedAt: now() });
        tx.update(db.collection("connectSpaces").doc(spaceId), { memberCount: admin.firestore.FieldValue.increment(1), updatedAt: now() });
    });
    await writeAudit(spaceId, uid, "acceptConnectInvite", "invite", inviteId);
    return { ok: true };
});

export const updateConnectMemberRole = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const spaceId = str(data, "spaceId");
    await requireSpaceRole(spaceId, uid, adminRoles);
    const targetUserId = str(data, "targetUserId");
    const role = str(data, "role", "member");
    await db.collection("connectSpaces").doc(spaceId).collection("members").doc(targetUserId).set({ role, updatedAt: now(), updatedBy: uid }, { merge: true });
    await writeAudit(spaceId, uid, "updateConnectMemberRole", "member", targetUserId, { role });
    return { ok: true };
});

export const createConnectChannel = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const spaceId = str(data, "spaceId");
    await requireSpaceRole(spaceId, uid, leaderRoles);
    const channelRef = db.collection("connectSpaces").doc(spaceId).collection("channels").doc(str(data, "channelId", db.collection("_ids").doc().id));
    await channelRef.set({ name: str(data, "name"), type: str(data, "type", "public"), visibility: str(data, "visibility", "publicToSpace"), allowedRoles: data.allowedRoles ?? ["owner", "admin", "moderator", "leader", "member"], aiSummaryEnabled: data.aiSummaryEnabled !== false, createdAt: now(), updatedAt: now(), createdBy: uid });
    await writeAudit(spaceId, uid, "createConnectChannel", "channel", channelRef.id);
    return { ok: true, channelId: channelRef.id };
});

export const sendConnectMessage = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const spaceId = str(data, "spaceId");
    const channelId = str(data, "channelId");
    await requireSpaceRole(spaceId, uid, ["owner", "admin", "moderator", "leader", "mentor", "creator", "teacher", "member", "paidMember"]);
    const body = str(data, "body");
    if (!body || body.length > 8000) throw new HttpsError("invalid-argument", "Message body is required");
    const moderation = moderationStatusForText(body);
    if (moderation.status === "blocked") throw new HttpsError("failed-precondition", "Message blocked by safety review");
    const messageRef = db.collection("connectSpaces").doc(spaceId).collection("channels").doc(channelId).collection("messages").doc();
    await messageRef.set({ senderId: uid, body, safetyStatus: moderation.status, riskReasons: moderation.reasons, aiEligible: data.aiEligible !== false, aiExcluded: data.aiExcluded === true, createdAt: now(), updatedAt: now(), createdBy: uid });
    await writeAudit(spaceId, uid, "sendConnectMessage", "message", messageRef.id, { channelId, safetyStatus: moderation.status });
    return { ok: true, messageId: messageRef.id, safetyStatus: moderation.status, riskReasons: moderation.reasons };
});

export const moderateConnectMessageBeforeSend = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const body = str(request.data as Record<string, unknown>, "body");
    const result = moderationStatusForText(body);
    return { ok: true, outcome: result.status, reasons: result.reasons };
});

export const createConnectAnnouncement = createConnectChannel;
export const createConnectMeeting = createWriteContract("meetings", leaderRoles, "createConnectMeeting");
export const joinConnectMeeting = createJoinContract("meetings", "joinConnectMeeting");
export const generateMeetingRecap = createAIContract("generateMeetingRecap");
export const createConnectEvent = createWriteContract("events", leaderRoles, "createConnectEvent");
export const createConnectBoard = createWriteContract("boards", leaderRoles, "createConnectBoard");
export const updateConnectBoardBlock = createWriteContract("boards", leaderRoles, "updateConnectBoardBlock");
export const createMarketplaceListing = createMarketplaceContract("createMarketplaceListing");
export const applyToMarketplaceListing = createJoinContract("marketplaceListings", "applyToMarketplaceListing", "applications");
export const moderateMarketplaceListing = createModerationContract("marketplaceListings", "moderateMarketplaceListing");
export const reportConnectContent = createReportContract("reportConnectContent");
export const reviewConnectReport = createModerationContract("reports", "reviewConnectReport");
export const generateConnectCatchUp = createAIContract("generateConnectCatchUp");
export const summarizeConnectChannel = createAIContract("summarizeConnectChannel");
export const summarizeConnectDM = createAIContract("summarizeConnectDM");
export const classifyConnectIntent = createAIContract("classifyConnectIntent");
export const extractTasksFromConnectThread = createAIContract("extractTasksFromConnectThread");
export const createEventFromThread = createAIContract("createEventFromThread");
export const createJobListingFromMessage = createAIContract("createJobListingFromMessage");
export const createBabysittingListingFromMessage = createAIContract("createBabysittingListingFromMessage");
export const createTutoringListingFromMessage = createAIContract("createTutoringListingFromMessage");
export const translateConnectMessage = createAIContract("translateConnectMessage");
export const rewriteConnectMessageTone = createAIContract("rewriteConnectMessageTone");
export const updateAIExclusions = createWriteContract("aiSummaries", adminRoles, "updateAIExclusions");
export const writeConnectAuditLog = createAuditContract();

export const createConnectCreatorProfile = createCreatorContract("createConnectCreatorProfile");
export const updateConnectCreatorProfile = createCreatorContract("updateConnectCreatorProfile");
export const createConnectTier = createCreatorSubcollectionContract("tiers", "createConnectTier");
export const updateConnectTier = createCreatorSubcollectionContract("tiers", "updateConnectTier");
export const subscribeToConnectTier = createPaymentContract("connectMemberships", "subscribeToConnectTier");
export const cancelConnectMembership = createPaymentContract("connectMemberships", "cancelConnectMembership");
export const createConnectPost = createCreatorSubcollectionContract("posts", "createConnectPost");
export const createConnectCollection = createCreatorSubcollectionContract("collections", "createConnectCollection");
export const createConnectProduct = createCreatorSubcollectionContract("products", "createConnectProduct");
export const purchaseConnectProduct = createPaymentContract("connectPurchases", "purchaseConnectProduct");
export const createConnectLiveSession = createCreatorSubcollectionContract("liveSessions", "createConnectLiveSession");
export const joinConnectLiveSession = createPaymentContract("connectPurchases", "joinConnectLiveSession");
export const purchaseConnectLiveSession = createPaymentContract("connectPurchases", "purchaseConnectLiveSession");
export const createConnectBooking = createPaymentContract("connectBookings", "createConnectBooking");
export const bookConnectService = createPaymentContract("connectBookings", "bookConnectService");
export const createGiftMembership = createPaymentContract("connectGiftMemberships", "createGiftMembership");
export const createSponsoredMembership = createPaymentContract("connectScholarships", "createSponsoredMembership");
export const generateCreatorInsights = createAIContract("generateCreatorInsights");
export const generateTierSuggestions = createAIContract("generateTierSuggestions");
export const moderateConnectMonetizedOffer = createModerationContract("creatorOffers", "moderateConnectMonetizedOffer", true);
export const reportConnectCreatorProfile = createGlobalReportContract("reportConnectCreatorProfile");
export const reportConnectProduct = createGlobalReportContract("reportConnectProduct");
export const reportConnectTier = createGlobalReportContract("reportConnectTier");
export const reportConnectLiveSession = createGlobalReportContract("reportConnectLiveSession");
export const processConnectPayout = createPaymentContract("connectPayouts", "processConnectPayout", true);

function createWriteContract(collectionName: string, roles: ConnectRole[], action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        await requireSpaceRole(spaceId, uid, roles);
        const ref = db.collection("connectSpaces").doc(spaceId).collection(collectionName).doc(str(data, "id", db.collection("_ids").doc().id));
        await ref.set({ ...data, createdBy: uid, updatedBy: uid, createdAt: now(), updatedAt: now(), moderationStatus: "pending", safetyStatus: "pending" }, { merge: true });
        await writeAudit(spaceId, uid, action, collectionName, ref.id);
        return { ok: true, id: ref.id };
    });
}

function createJoinContract(collectionName: string, action: string, subcollection = "participants") {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        const targetId = str(data, "targetId");
        await requireSpaceRole(spaceId, uid, ["owner", "admin", "moderator", "leader", "mentor", "creator", "teacher", "member", "paidMember"]);
        await db.collection("connectSpaces").doc(spaceId).collection(collectionName).doc(targetId).collection(subcollection).doc(uid).set({ userId: uid, status: "pending", createdAt: now(), updatedAt: now() }, { merge: true });
        await writeAudit(spaceId, uid, action, collectionName, targetId);
        return { ok: true };
    });
}

function createMarketplaceContract(action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        await requireSpaceRole(spaceId, uid, ["owner", "admin", "moderator", "leader", "member", "paidMember"]);
        const category = str(data, "category", "Local Help");
        if (!publicMarketplaceCategories.includes(category)) throw new HttpsError("invalid-argument", "Unsupported marketplace category");
        const moderation = moderationStatusForText(`${str(data, "title")} ${str(data, "description")}`);
        const ref = db.collection("connectSpaces").doc(spaceId).collection("marketplaceListings").doc();
        const payload = { ...data, category, createdBy: uid, createdAt: now(), updatedAt: now(), safetyStatus: moderation.status, moderationStatus: moderation.status === "allowed" ? "approved" : "pending", riskReasons: moderation.reasons, trustIndicatorsServerOwned: true };
        await ref.set(payload);
        await db.collection("connectMarketplaceGlobal").doc(ref.id).set({ ...payload, spaceId, listingId: ref.id });
        await writeAudit(spaceId, uid, action, "marketplaceListing", ref.id, { safetyStatus: moderation.status });
        return { ok: true, listingId: ref.id, safetyStatus: moderation.status, riskReasons: moderation.reasons };
    });
}

function createModerationContract(collectionName: string, action: string, global = false) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        if (!global) await requireSpaceRole(spaceId, uid, moderatorRoles);
        const targetId = str(data, "targetId");
        const status = str(data, "status", "needs_review");
        const ref = global ? db.collection(collectionName).doc(targetId) : db.collection("connectSpaces").doc(spaceId).collection(collectionName).doc(targetId);
        await ref.set({ moderationStatus: status, safetyStatus: status, reviewedBy: uid, reviewedAt: now(), updatedAt: now() }, { merge: true });
        if (spaceId) await writeAudit(spaceId, uid, action, collectionName, targetId, { status });
        return { ok: true };
    });
}

function createAIContract(action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        if (spaceId) await requireSpaceRole(spaceId, uid, ["owner", "admin", "moderator", "leader", "mentor", "creator", "teacher", "member", "paidMember"]);
        const summaryRef = spaceId ? db.collection("connectSpaces").doc(spaceId).collection("aiSummaries").doc() : db.collection("connectActivity").doc(uid).collection("items").doc();
        await summaryRef.set({ action, requestedBy: uid, status: "contract_only_pending_ai_provider", accessScope: data.accessScope ?? null, excludesAIExcludedContent: true, excludesPaidWithoutAccess: true, excludesDeletedContent: true, excludesYouthProtectedWithoutAccess: true, createdAt: now() });
        if (spaceId) await writeAudit(spaceId, uid, action, "aiSummary", summaryRef.id);
        return { ok: true, id: summaryRef.id, status: "contract_only_pending_ai_provider" };
    });
}

function createReportContract(action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        await requireSpaceRole(spaceId, uid, ["owner", "admin", "moderator", "leader", "mentor", "creator", "teacher", "member", "paidMember", "guest"]);
        const ref = db.collection("connectSpaces").doc(spaceId).collection("reports").doc();
        await ref.set({ ...data, reporterId: uid, status: "pending", createdAt: now(), updatedAt: now() });
        await writeAudit(spaceId, uid, action, "report", ref.id);
        return { ok: true, reportId: ref.id };
    });
}

function createGlobalReportContract(action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const ref = db.collection("connectUserSafety").doc(uid).collection("reports").doc();
        await ref.set({ ...data, reporterId: uid, action, status: "pending", createdAt: now(), updatedAt: now() });
        return { ok: true, reportId: ref.id };
    });
}

function createCreatorContract(action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const creatorId = str(data, "creatorId", uid);
        await db.collection("connectCreatorProfiles").doc(creatorId).set({ ...data, ownerId: uid, trustBadges: data.trustBadges ?? [], verificationBadges: data.verificationBadges ?? [], safetyStatus: "pending", moderationStatus: "pending", updatedAt: now(), createdAt: now() }, { merge: true });
        return { ok: true, creatorId };
    });
}

function createCreatorSubcollectionContract(subcollection: string, action: string) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const creatorId = str(data, "creatorId", uid);
        const profile = await db.collection("connectCreatorProfiles").doc(creatorId).get();
        if (profile.data()?.ownerId !== uid) throw new HttpsError("permission-denied", "Creator ownership required");
        const text = `${str(data, "title")} ${str(data, "description")} ${str(data, "benefits")}`;
        const moderation = moderationStatusForText(text);
        const ref = db.collection("connectCreatorProfiles").doc(creatorId).collection(subcollection).doc(str(data, "id", db.collection("_ids").doc().id));
        await ref.set({ ...data, createdBy: uid, createdAt: now(), updatedAt: now(), safetyStatus: moderation.status, moderationStatus: moderation.status === "allowed" ? "approved" : "pending", riskReasons: moderation.reasons, paymentStateServerOwned: true }, { merge: true });
        return { ok: true, id: ref.id, safetyStatus: moderation.status, riskReasons: moderation.reasons };
    });
}

function createPaymentContract(collectionName: string, action: string, adminOnly = false) {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        if (adminOnly && request.auth?.uid !== uid) throw new HttpsError("permission-denied", "Admin required");
        const data = request.data as Record<string, unknown>;
        const ref = db.collection(collectionName).doc(str(data, "id", db.collection("_ids").doc().id));
        await ref.set({ ...data, userId: uid, action, paymentState: "server_contract_pending_provider", accessGranted: false, createdAt: now(), updatedAt: now() }, { merge: true });
        return { ok: true, id: ref.id, paymentState: "server_contract_pending_provider" };
    });
}

function createAuditContract() {
    return onCall({ enforceAppCheck: true }, async (request) => {
        const uid = requireAuth(request);
        const data = request.data as Record<string, unknown>;
        const spaceId = str(data, "spaceId");
        await requireSpaceRole(spaceId, uid, adminRoles);
        await writeAudit(spaceId, uid, str(data, "action", "manualAudit"), str(data, "targetType", "unknown"), str(data, "targetId", "unknown"), data.metadata as Record<string, unknown> ?? {});
        return { ok: true };
    });
}

export async function createConnectStripeCheckoutSession(
    uid: string,
    target: { creatorId: string; tierId?: string; productId?: string; targetId?: string },
    connectKind: ConnectPaymentKind,
    action: string,
    mode: "subscription" | "payment"
) {
    const creatorId = target.creatorId;
    const targetId = target.tierId ?? target.productId ?? target.targetId;
    if (!creatorId || !targetId) {
        throw new HttpsError("invalid-argument", "creatorId and target id are required");
    }

    const collectionName = connectKind === "tier" ? "tiers" : "products";
    const targetSnap = await db
        .collection("connectCreatorProfiles")
        .doc(creatorId)
        .collection(collectionName)
        .doc(targetId)
        .get();
    const targetData = targetSnap.data() ?? {};
    if (targetData.moderationStatus !== "approved") {
        throw new HttpsError("failed-precondition", "Connect item is not approved for checkout");
    }

    const stripePriceId = str(targetData, "stripePriceId");
    if (!stripePriceId) {
        throw new HttpsError("failed-precondition", "Connect item is missing Stripe price configuration");
    }

    const paymentRef = db.collection("connectPayments").doc();
    const connectPaymentId = paymentRef.id;
    const metadata = {
        connectKind: String(connectKind),
        creatorId,
        targetId,
        userId: uid,
        connectPaymentId,
    };

    const stripe = new StripeConstructor(process.env.STRIPE_SECRET_KEY ?? "");
    const session = await stripe.checkout.sessions.create({
        mode,
        line_items: [{ price: stripePriceId, quantity: 1 }],
        success_url: "https://amen.app/connect/checkout/success",
        cancel_url: "https://amen.app/connect/checkout/cancel",
        metadata,
        subscription_data: mode === "subscription" ? { metadata } : undefined,
    });

    await paymentRef.set({
        userId: uid,
        action,
        connectKind,
        creatorId,
        targetId,
        provider: "stripe",
        stripeCheckoutSessionId: session.id,
        paymentState: "checkout_created",
        accessGranted: false,
        createdAt: now(),
        updatedAt: now(),
    });

    return {
        checkoutUrl: session.url,
        paymentState: "checkout_created",
        accessGranted: false,
    };
}

export async function handleConnectStripeEvent(
    event: ConnectStripeEvent,
    dbInstance: admin.firestore.Firestore,
    stripe: ConnectStripeClient
): Promise<void> {
    if (event.type !== "checkout.session.completed") return;

    const session = event.data.object as ConnectStripeSession;
    const sessionMetadata = session.metadata ?? {};
    const subscriptionId = typeof session.subscription === "string" ? session.subscription : null;
    const subscription = subscriptionId
        ? await stripe.subscriptions.retrieve(subscriptionId) as ConnectStripeSubscription
        : null;
    const metadata = subscription?.metadata && Object.keys(subscription.metadata).length > 0
        ? subscription.metadata
        : sessionMetadata;

    const connectKind = metadata.connectKind;
    const creatorId = metadata.creatorId;
    const targetId = metadata.targetId;
    const userId = metadata.userId;
    const connectPaymentId = metadata.connectPaymentId ?? session.id;
    if (!connectKind || !creatorId || !targetId || !userId) return;

    if (session.mode === "subscription" && subscription) {
        await dbInstance.collection("connectMemberships").doc(connectPaymentId).set({
            userId,
            creatorId,
            targetId,
            connectKind,
            membershipStatus: subscription.status ?? "active",
            accessGranted: true,
            source: "stripe_subscription",
            stripeSubscriptionId: subscription.id,
            stripeCustomerId: typeof subscription.customer === "string"
                ? subscription.customer
                : subscription.customer?.id ?? session.customer ?? null,
            updatedAt: now(),
        }, { merge: true });
        return;
    }

    if (session.mode === "payment") {
        await dbInstance.collection("connectPurchases").doc(connectPaymentId).set({
            userId,
            creatorId,
            targetId,
            connectKind,
            purchaseState: "active",
            accessGranted: true,
            source: "stripe_checkout",
            stripeCheckoutSessionId: session.id,
            updatedAt: now(),
        }, { merge: true });
    }
}

export async function collectAuthorizedAIContext(
    uid: string,
    action: string,
    scope: { spaceId: string; channelId?: string }
): Promise<string> {
    const messagesRef = db
        .collection("connectSpaces")
        .doc(scope.spaceId)
        .collection("channels")
        .doc(scope.channelId ?? "general")
        .collection("messages");
    const snap = await messagesRef.orderBy("createdAt", "desc").limit(50).get();
    const visibleBodies = snap.docs
        .map((doc) => doc.data())
        .filter((message) => !message.deletedAt)
        .filter((message) => message.aiExcluded !== true)
        .filter((message) => message.visibility !== "confidential")
        .filter((message) => message.visibility !== "youthProtected")
        .filter((message) => !message.requiredTierId)
        .map((message) => String(message.body ?? "").trim())
        .filter(Boolean);

    return [`action:${action}`, `uid:${uid}`, ...visibleBodies].join("\n");
}

export async function runConnectAI(action: string, authorizedContext: string): Promise<unknown> {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
            action,
            context: authorizedContext.slice(0, 12000),
        }),
    });

    if (!response.ok) {
        throw new HttpsError("internal", "Connect AI provider failed");
    }

    return response.json();
}
