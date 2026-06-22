import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();
const REGION = "us-central1";
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

type CallableRequest = {
    auth?: {
        uid?: string;
        token?: Record<string, unknown>;
    };
    app?: { appId?: string };
    data?: Record<string, unknown>;
};

type VerificationStatus = "unverified" | "pending" | "verified" | "rejected";
type VerificationLevel = "basic" | "official" | "trusted";
type ModerationState = "approved" | "rejected" | "needsReview" | "blocked";
type LivestreamProvider = "youtube" | "vimeo" | "direct_rtmp" | "direct_hls" | "embedded" | "unknown";
type ConfidenceLevel = "low" | "medium" | "high" | "verified";

function requireAuth(request: CallableRequest): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function requireAppCheck(request: CallableRequest): void {
    if (IS_EMULATOR) return;
    if (!request.app?.appId) {
        throw new HttpsError("failed-precondition", "App Check token required.");
    }
}

function requireAdmin(request: CallableRequest): string {
    const uid = requireAuth(request);
    if (request.auth?.token?.admin !== true) {
        throw new HttpsError("permission-denied", "Admin privileges required.");
    }
    return uid;
}

function readChurchId(request: CallableRequest): string {
    const churchId = String(request.data?.churchId ?? "").trim();
    if (!churchId) {
        throw new HttpsError("invalid-argument", "churchId is required.");
    }
    return churchId;
}

function readOptionalString(data: Record<string, unknown> | undefined, key: string): string | null {
    const value = String(data?.[key] ?? "").trim();
    return value ? value : null;
}

function readStringList(data: Record<string, unknown> | undefined, key: string): string[] {
    const value = data?.[key];
    if (!Array.isArray(value)) return [];
    return value.map((item) => String(item ?? "").trim()).filter(Boolean);
}

function normalizeWebsiteDomain(value: string | null): string | null {
    if (!value) return null;
    try {
        const normalized = value.startsWith("http://") || value.startsWith("https://") ? value : `https://${value}`;
        const url = new URL(normalized);
        return url.hostname.replace(/^www\./i, "").toLowerCase();
    } catch {
        return null;
    }
}

function confidenceLevelFor(value: number, verified = false): ConfidenceLevel {
    if (verified || value >= 0.9) return "verified";
    if (value >= 0.7) return "high";
    if (value >= 0.35) return "medium";
    return "low";
}

function buildSource(
    id: string,
    type: string,
    title: string,
    detail: string | null,
    verified: boolean,
    url?: string | null
): Record<string, unknown> {
    return {
        id,
        type,
        title,
        detail,
        url: url ?? null,
        verified,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

async function loadChurch(churchId: string): Promise<FirebaseFirestore.DocumentSnapshot> {
    const snapshot = await db.collection("churches").doc(churchId).get();
    if (!snapshot.exists) {
        throw new HttpsError("not-found", "Church not found.");
    }
    return snapshot;
}

async function assertChurchAdmin(uid: string, churchId: string): Promise<FirebaseFirestore.DocumentData> {
    const snapshot = await db.collection("church_admins").doc(uid).get();
    const data = snapshot.data() ?? {};
    const churchIds = Array.isArray(data.churchIds) ? data.churchIds.map((item: unknown) => String(item)) : [];
    if (!churchIds.includes(churchId)) {
        throw new HttpsError("permission-denied", "You are not assigned to this church.");
    }
    return data;
}

function computeVerificationConfidence(input: {
    websiteDomainMatches: boolean;
    officialWebsiteVerified: boolean;
    livestreamVerified: boolean;
    ownershipClaimed: boolean;
    reviewApproved: boolean;
}): number {
    let confidence = 0.2;
    if (input.ownershipClaimed) confidence += 0.15;
    if (input.websiteDomainMatches) confidence += 0.2;
    if (input.officialWebsiteVerified) confidence += 0.15;
    if (input.livestreamVerified) confidence += 0.1;
    if (input.reviewApproved) confidence += 0.2;
    return Math.max(0.2, Math.min(0.98, confidence));
}

function computeModerationDecision(aiScores: Record<string, number>, reasons: string[]): {
    moderationState: ModerationState;
    escalated: boolean;
} {
    const maxScore = Math.max(...Object.values(aiScores), 0);
    if (maxScore >= 0.92) {
        reasons.push("high_risk_score");
        return { moderationState: "blocked", escalated: true };
    }
    if (maxScore >= 0.72 || reasons.length > 0) {
        return { moderationState: "needsReview", escalated: true };
    }
    return { moderationState: "approved", escalated: false };
}

function buildGroundedSummary(churchId: string, churchData: FirebaseFirestore.DocumentData): Record<string, unknown> {
    const website = readOptionalString(churchData, "website");
    const livestreamTitle = readOptionalString(churchData, "livestreamTitle");
    const serviceTimes = Array.isArray(churchData.serviceTimes) ? churchData.serviceTimes : [];
    const verificationStatus = String(churchData.verificationStatus ?? "unverified") as VerificationStatus;
    const profileConfidence = Number(churchData.profileConfidence ?? 0.2);
    const confidence = Math.max(0.2, Math.min(0.95, profileConfidence));
    const verified = verificationStatus === "verified";

    const sources = [
        buildSource(`${churchId}_profile`, verified ? "verifiedMetadata" : "publicMetadata", "Church profile", "Church directory metadata", verified),
        ...(website ? [buildSource(`${churchId}_website`, "officialWebsite", "Official website", "Public church website", Boolean(churchData.officialWebsiteVerified), website)] : []),
        ...(serviceTimes.length > 0 ? [buildSource(`${churchId}_services`, "serviceSchedule", "Service schedule", "Structured service times", verified)] : []),
        ...(livestreamTitle ? [buildSource(`${churchId}_livestream`, "livestream", livestreamTitle, "Approved livestream metadata", Boolean(churchData.livestreamVerified))] : []),
    ];

    const summary = verified
        ? "This summary is grounded in verified church profile data and approved church signals."
        : "This summary is based on public church metadata and has not yet been fully confirmed by the church.";

    return {
        churchId,
        summary,
        confidence,
        confidenceLevel: confidenceLevelFor(confidence, verified),
        sources,
        fallbackMessage: verified
            ? "Grounded in verified church information."
            : "I do not have enough verified information yet.",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

export const submitChurchVerificationClaim = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const uid = requireAuth(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const churchSnapshot = await loadChurch(churchId);
    const churchData = churchSnapshot.data() ?? {};

    const claimantEmail = readOptionalString(request.data, "claimantEmail");
    const officialWebsite = readOptionalString(request.data, "officialWebsite") ?? readOptionalString(churchData, "website");
    const proofURL = readOptionalString(request.data, "proofUrl");
    const livestreamURL = readOptionalString(request.data, "livestreamUrl");
    const websiteDomain = normalizeWebsiteDomain(officialWebsite);
    const emailDomain = claimantEmail?.split("@")[1]?.toLowerCase() ?? null;
    const websiteDomainMatches = Boolean(websiteDomain && emailDomain && websiteDomain === emailDomain);
    const officialWebsiteVerified = websiteDomainMatches || Boolean(proofURL);
    const livestreamVerified = Boolean(livestreamURL);
    const profileConfidence = computeVerificationConfidence({
        websiteDomainMatches,
        officialWebsiteVerified,
        livestreamVerified,
        ownershipClaimed: true,
        reviewApproved: false,
    });

    const claimRef = churchSnapshot.ref.collection("verification_claims").doc(uid);
    await claimRef.set({
        churchId,
        uid,
        claimantEmail,
        officialWebsite,
        proofUrl: proofURL,
        livestreamUrl: livestreamURL,
        websiteDomainMatches,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await churchSnapshot.ref.set({
        verificationStatus: "pending",
        verificationLevel: officialWebsiteVerified ? "official" : "basic",
        ownershipClaimed: true,
        officialWebsiteVerified,
        livestreamVerified,
        profileConfidence,
        moderationStatus: churchData.moderationStatus ?? "approved",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    logger.info("submitChurchVerificationClaim: queued", { uid, churchId, websiteDomainMatches });
    return {
        churchId,
        verificationStatus: "pending" as VerificationStatus,
        verificationLevel: officialWebsiteVerified ? "official" as VerificationLevel : "basic" as VerificationLevel,
        profileConfidence,
    };
});

export const reviewChurchVerificationClaim = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const reviewerId = requireAdmin(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const claimUid = String(request.data?.claimUid ?? "").trim();
    const status = String(request.data?.status ?? "").trim() as VerificationStatus;
    const approved = status === "verified";
    if (!claimUid || !["verified", "rejected", "pending"].includes(status)) {
        throw new HttpsError("invalid-argument", "Valid claimUid and status are required.");
    }

    const churchSnapshot = await loadChurch(churchId);
    const claimRef = churchSnapshot.ref.collection("verification_claims").doc(claimUid);
    const claimSnapshot = await claimRef.get();
    const claimData = claimSnapshot.data() ?? {};

    const level = approved
        ? ((Boolean(claimData.officialWebsiteVerified) && Boolean(claimData.livestreamUrl)) ? "trusted" : "official")
        : "basic";
    const profileConfidence = computeVerificationConfidence({
        websiteDomainMatches: Boolean(claimData.websiteDomainMatches),
        officialWebsiteVerified: Boolean(claimData.officialWebsite ?? claimData.proofUrl),
        livestreamVerified: Boolean(claimData.livestreamUrl),
        ownershipClaimed: true,
        reviewApproved: approved,
    });

    await db.runTransaction(async (transaction) => {
        transaction.set(claimRef, {
            status,
            reviewedBy: reviewerId,
            reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        transaction.set(churchSnapshot.ref, {
            verificationStatus: status,
            verificationLevel: level,
            verifiedAt: approved ? admin.firestore.FieldValue.serverTimestamp() : null,
            verifiedBy: approved ? reviewerId : null,
            officialWebsiteVerified: Boolean(claimData.officialWebsite ?? claimData.proofUrl),
            livestreamVerified: Boolean(claimData.livestreamUrl),
            ownershipClaimed: true,
            profileConfidence,
            moderationStatus: "approved",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });

    logger.info("reviewChurchVerificationClaim: completed", { reviewerId, churchId, claimUid, status });
    return {
        churchId,
        verificationStatus: status,
        verificationLevel: level,
        profileConfidence,
    };
});

export const submitChurchProfileEdit = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const uid = requireAuth(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const adminProfile = await assertChurchAdmin(uid, churchId);

    const allowedFields = [
        "serviceTimes",
        "livestreamUrl",
        "accessibility",
        "parkingInfo",
        "ministries",
        "events",
        "prayerNights",
        "firstTimeVisitorInfo",
        "mediaUploads",
    ];

    const proposedChanges = Object.fromEntries(
        Object.entries(request.data ?? {}).filter(([key]) => allowedFields.includes(key))
    );

    if (Object.keys(proposedChanges).length === 0) {
        throw new HttpsError("invalid-argument", "No editable fields were provided.");
    }

    const queueRef = db.collection("churches").doc(churchId).collection("profile_edit_queue").doc();
    await queueRef.set({
        churchId,
        submittedBy: uid,
        submitterRole: adminProfile.role ?? "editor",
        changes: proposedChanges,
        moderationState: "needsReview",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("submitChurchProfileEdit: queued", { uid, churchId, fields: Object.keys(proposedChanges) });
    return { churchId, queuedEditId: queueRef.id, moderationState: "needsReview" };
});

export const queueChurchMediaModeration = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const uid = requireAuth(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    await assertChurchAdmin(uid, churchId);

    const type = readOptionalString(request.data, "type") ?? "image";
    const source = readOptionalString(request.data, "source") ?? "church_upload";
    const caption = readOptionalString(request.data, "caption") ?? "";
    const ocrText = readOptionalString(request.data, "ocrText") ?? "";
    const aiScores = {
        nudity: Number(request.data?.nudityScore ?? 0),
        explicit: Number(request.data?.explicitScore ?? 0),
        hate: Number(request.data?.hateScore ?? 0),
        misleading: Number(request.data?.misleadingScore ?? 0),
        impersonation: Number(request.data?.impersonationScore ?? 0),
        spam: Number(request.data?.spamScore ?? 0),
    };
    const reasons = [
        ...((caption.length > 500 || ocrText.length > 500) ? ["long_text_needs_review"] : []),
        ...(caption.toLowerCase().includes("official") && source !== "church_upload" ? ["impersonation_risk"] : []),
    ];
    const decision = computeModerationDecision(aiScores, reasons);
    const queueRef = db.collection("moderation_queue").doc();

    await queueRef.set({
        type,
        source,
        churchId,
        uploadedBy: uid,
        moderationState: decision.moderationState,
        moderationReasons: reasons,
        aiScores,
        escalated: decision.escalated,
        reviewedBy: null,
        reviewedAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("queueChurchMediaModeration: queued", { churchId, queueId: queueRef.id, moderationState: decision.moderationState });
    return { itemId: queueRef.id, moderationState: decision.moderationState, escalated: decision.escalated };
});

export const reviewChurchModerationItem = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const reviewerId = requireAdmin(request as CallableRequest);
    const itemId = String(request.data?.itemId ?? "").trim();
    const moderationState = String(request.data?.moderationState ?? "").trim() as ModerationState;
    if (!itemId || !["approved", "rejected", "needsReview", "blocked"].includes(moderationState)) {
        throw new HttpsError("invalid-argument", "Valid itemId and moderationState are required.");
    }

    const queueRef = db.collection("moderation_queue").doc(itemId);
    const auditRef = queueRef.collection("history").doc();
    await db.runTransaction(async (transaction) => {
        const queueSnapshot = await transaction.get(queueRef);
        const current = queueSnapshot.data() ?? {};
        transaction.set(queueRef, {
            moderationState,
            escalated: moderationState !== "approved",
            reviewedBy: reviewerId,
            reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.set(auditRef, {
            previousState: current.moderationState ?? "needsReview",
            newState: moderationState,
            reviewedBy: reviewerId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    return { itemId, moderationState, reviewedBy: reviewerId };
});

export const refreshChurchLivestreamState = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const churchSnapshot = await loadChurch(churchId);
    const provider = (readOptionalString(request.data, "provider") ?? "unknown") as LivestreamProvider;
    const streamId = readOptionalString(request.data, "streamId") ?? provider;
    const title = readOptionalString(request.data, "title") ?? "Church livestream";
    const streamUrl = readOptionalString(request.data, "streamUrl");
    const thumbnailUrl = readOptionalString(request.data, "thumbnailUrl");
    const liveNow = Boolean(request.data?.liveNow);
    const ingestConfidence = Number(request.data?.ingestConfidence ?? (liveNow ? 0.72 : 0.4));
    const verified = Boolean(churchSnapshot.data()?.livestreamVerified);

    await churchSnapshot.ref.collection("livestreams").doc(streamId).set({
        provider,
        title,
        thumbnailUrl,
        streamUrl,
        liveNow,
        startedAt: liveNow ? admin.firestore.FieldValue.serverTimestamp() : null,
        scheduledAt: null,
        viewerSignal: Number(request.data?.viewerSignal ?? 0),
        ingestConfidence,
        sources: [
            buildSource(`${churchId}_${streamId}`, "livestream", title, "Provider-reported livestream metadata", verified, streamUrl),
        ],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await churchSnapshot.ref.collection("live_state").doc("current").set({
        state: liveNow ? "live" : "unknown",
        title: liveNow ? "Live nearby" : "Not live right now",
        description: liveNow ? "Provider API indicates the stream is live." : "Current livestream status is not confirmed.",
        livestreamUrl: streamUrl,
        confidence: ingestConfidence,
        confidenceLevel: confidenceLevelFor(ingestConfidence, verified),
        sources: [
            buildSource(`${churchId}_${streamId}_state`, "livestream", title, "Livestream ingest state", verified, streamUrl),
        ],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { churchId, streamId, liveNow, ingestConfidence };
});

export const syncYouTubeChurchStreams = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    requireAdmin(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const channelId = readOptionalString(request.data, "channelId");
    if (!channelId) {
        throw new HttpsError("invalid-argument", "channelId is required.");
    }

    const syncRef = db.collection("churches").doc(churchId).collection("livestream_sync").doc("youtube");
    await syncRef.set({
        provider: "youtube",
        channelId,
        status: "scheduled",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
        churchId,
        provider: "youtube",
        status: "scheduled",
        note: "YouTube provider sync is stubbed and ready for API-backed ingestion.",
    };
});

export const updateChurchLiveSignals = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    requireAdmin(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const viewerSignal = Number(request.data?.viewerSignal ?? 0);
    const prayerActivity = Number(request.data?.prayerActivity ?? 0);
    const visitorActivity = Number(request.data?.visitorActivity ?? 0);
    const communityActivity = Number(request.data?.communityActivity ?? 0);
    const total = Math.max(viewerSignal, prayerActivity, visitorActivity, communityActivity);
    const confidence = Math.max(0.25, Math.min(0.9, total > 0 ? 0.55 : 0.3));

    let title = "Community engagement active tonight";
    if (prayerActivity >= total && prayerActivity > 0) title = "Prayer activity trending up";
    if (viewerSignal >= total && viewerSignal > 0) title = "Livestream engagement high";
    if (visitorActivity >= total && visitorActivity > 0) title = "New visitor activity increased";

    await db.collection("churches").doc(churchId).collection("pulse").doc("current").set({
        title,
        detail: "Atmospheric pulse only. No public rankings or attendance comparisons.",
        confidence,
        confidenceLevel: confidenceLevelFor(confidence),
        sources: [
            buildSource(`${churchId}_pulse`, "verifiedMetadata", "Church pulse", "Aggregated private church signals", false),
        ],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { churchId, title, confidence };
});

export const regenerateChurchGroundedSummary = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    requireAdmin(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const churchSnapshot = await loadChurch(churchId);
    const summary = buildGroundedSummary(churchId, churchSnapshot.data() ?? {});

    await churchSnapshot.ref.collection("berean_grounding").doc("current").set(summary, { merge: true });
    await churchSnapshot.ref.set({
        profileSources: summary.sources,
        profileConfidence: summary.confidence,
        profileConfidenceLevel: summary.confidenceLevel,
        profileConfidenceNote: summary.fallbackMessage,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
        churchId,
        confidence: summary.confidence,
        confidenceLevel: summary.confidenceLevel,
        fallbackMessage: summary.fallbackMessage,
    };
});

export const generateGroundedChurchResponse = onCall({ enforceAppCheck: true, region: REGION }, async (request) => {
    requireAppCheck(request as CallableRequest);
    requireAuth(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    const groundingSnapshot = await db.collection("churches").doc(churchId).collection("berean_grounding").doc("current").get();
    const grounding = groundingSnapshot.data();

    if (!grounding) {
        return {
            churchId,
            response: "I do not have enough verified information yet.",
            confidence: 0.2,
            confidenceLevel: "low" as ConfidenceLevel,
            sources: [],
        };
    }

    return {
        churchId,
        response: grounding.summary,
        confidence: grounding.confidence ?? 0.2,
        confidenceLevel: grounding.confidenceLevel ?? "low",
        sources: grounding.sources ?? [],
        fallbackMessage: grounding.fallbackMessage ?? "This appears based on public church metadata.",
    };
});
