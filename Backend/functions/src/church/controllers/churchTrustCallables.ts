import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

type ConfidenceLevel = "low" | "medium" | "high" | "verified";
type ChurchModerationState = "approved" | "rejected" | "needsReview" | "blocked";
type ChurchLivestreamProvider = "youtube" | "vimeo" | "direct_rtmp" | "direct_hls" | "embedded" | "unknown";

type GroundingSource = {
    id: string;
    type:
        | "verifiedMetadata"
        | "officialWebsite"
        | "approvedMedia"
        | "livestream"
        | "serviceSchedule"
        | "adminProvided"
        | "userPreference"
        | "publicMetadata";
    title: string;
    detail?: string | null;
    url?: string | null;
    verified: boolean;
    updatedAt?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue | null;
};

type ChurchAdminRecord = {
    churchIds: string[];
    role: "owner" | "admin" | "editor" | "moderator";
};

type LivestreamRecord = {
    provider: ChurchLivestreamProvider;
    title: string;
    thumbnailUrl?: string | null;
    streamUrl: string;
    liveNow: boolean;
    startedAt?: FirebaseFirestore.Timestamp | null;
    scheduledAt?: FirebaseFirestore.Timestamp | null;
    viewerSignal?: number | null;
    ingestConfidence: number;
    updatedAt: FirebaseFirestore.FieldValue;
    sources: GroundingSource[];
};

type ModerationInput = {
    labels?: string[];
    ocrText?: string;
    captionText?: string;
    uploadVelocity?: number;
    impersonationSignal?: number;
};

type ModerationResult = {
    moderationState: ChurchModerationState;
    moderationReasons: string[];
    aiScores: Record<string, number>;
    escalated: boolean;
};

const db = admin.firestore();

function requireAuth(request: {auth?: {uid?: string}}): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return uid;
}

function levelForConfidence(confidence: number): ConfidenceLevel {
    if (confidence < 0.35) return "low";
    if (confidence < 0.7) return "medium";
    if (confidence < 0.9) return "high";
    return "verified";
}

function clampScore(value: number): number {
    return Math.max(0, Math.min(1, Number(value.toFixed(3))));
}

function scoreChurchProfile(input: {
    verificationStatus?: string | null;
    officialWebsiteVerified?: boolean;
    livestreamVerified?: boolean;
    ownershipClaimed?: boolean;
    approvedMediaCount?: number;
    serviceTimeCount?: number;
    hasAdminEdits?: boolean;
}): number {
    let score = 0.2;
    if (input.ownershipClaimed) score += 0.15;
    if (input.officialWebsiteVerified) score += 0.2;
    if (input.livestreamVerified) score += 0.15;
    if ((input.approvedMediaCount ?? 0) > 0) score += Math.min(0.1, (input.approvedMediaCount ?? 0) * 0.02);
    if ((input.serviceTimeCount ?? 0) > 0) score += 0.1;
    if (input.hasAdminEdits) score += 0.1;
    if (input.verificationStatus === "verified") score += 0.2;
    return clampScore(score);
}

async function assertChurchAccess(uid: string, churchId: string, acceptedRoles: ChurchAdminRecord["role"][]): Promise<void> {
    const snapshot = await db.collection("church_admins").doc(uid).get();
    const adminRecord = snapshot.exists ? snapshot.data() as ChurchAdminRecord : null;

    if (!adminRecord || !Array.isArray(adminRecord.churchIds) || !adminRecord.churchIds.includes(churchId)) {
        throw new HttpsError("permission-denied", "You are not assigned to this church.");
    }
    if (!acceptedRoles.includes(adminRecord.role)) {
        throw new HttpsError("permission-denied", "You are not assigned to this church.");
    }
}

function keywordScore(text: string, matches: string[], weight: number): number {
    return matches.some((match) => text.includes(match)) ? weight : 0;
}

function evaluateModeration(input: ModerationInput): ModerationResult {
    const labelText = (input.labels ?? []).join(" ").toLowerCase();
    const bodyText = `${input.ocrText ?? ""} ${input.captionText ?? ""}`.toLowerCase();

    const nudity = keywordScore(labelText, ["nudity", "sexual", "explicit"], 0.92);
    const hate = keywordScore(bodyText, ["hate", "extremist", "supremacy"], 0.96);
    const misleading = keywordScore(bodyText, ["official stream", "verified", "pastor"], 0.45);
    const spam = Math.min(1, (input.uploadVelocity ?? 0) / 10);
    const impersonation = Math.max(0, Math.min(1, input.impersonationSignal ?? 0));

    const moderationReasons: string[] = [];
    let moderationState: ChurchModerationState = "approved";
    let escalated = false;

    if (nudity >= 0.9) moderationReasons.push("explicit_content");
    if (hate >= 0.85) moderationReasons.push("hate_or_extremism");
    if (impersonation >= 0.75) moderationReasons.push("impersonation_risk");
    if (misleading >= 0.8) moderationReasons.push("misleading_imagery");
    if (spam >= 0.8) moderationReasons.push("spam_upload_pattern");

    if (nudity >= 0.9 || hate >= 0.85) {
        moderationState = "blocked";
    } else if (moderationReasons.length > 0) {
        moderationState = "needsReview";
        escalated = true;
    }

    return {
        moderationState,
        moderationReasons,
        aiScores: {
            nudity,
            hate,
            misleading,
            spam,
            impersonation,
            confidence: scoreChurchProfile({
                approvedMediaCount: moderationState === "approved" ? 1 : 0,
            }),
        },
        escalated,
    };
}

function buildLivestreamRecord(probe: {
    provider: ChurchLivestreamProvider;
    title: string;
    streamUrl: string;
    thumbnailUrl?: string | null;
    scheduledAt?: Date | null;
    startedAt?: Date | null;
    viewerSignal?: number | null;
    providerConfirmedLive?: boolean;
    websiteConfirmed?: boolean;
}): LivestreamRecord {
    let confidence = 0.2;
    if (probe.providerConfirmedLive) confidence += 0.45;
    if (probe.websiteConfirmed) confidence += 0.2;
    if (probe.startedAt) confidence += 0.1;
    if ((probe.viewerSignal ?? 0) > 0) confidence += 0.1;
    confidence = Math.max(0.1, Math.min(0.98, Number(confidence.toFixed(3))));

    const sources: GroundingSource[] = [
        {
            id: `provider:${probe.provider}`,
            type: "livestream",
            title: `${probe.provider} provider signal`,
            detail: probe.providerConfirmedLive ? "Provider API indicates live state." : "Provider metadata only.",
            url: probe.streamUrl,
            verified: probe.providerConfirmedLive === true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    ];

    if (probe.websiteConfirmed) {
        sources.push({
            id: "official-site",
            type: "officialWebsite",
            title: "Official church website",
            detail: "Stream link matched from official church web metadata.",
            url: probe.streamUrl,
            verified: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    return {
        provider: probe.provider,
        title: probe.title,
        thumbnailUrl: probe.thumbnailUrl ?? null,
        streamUrl: probe.streamUrl,
        liveNow: confidence >= 0.75 && probe.providerConfirmedLive === true,
        startedAt: probe.startedAt ? admin.firestore.Timestamp.fromDate(probe.startedAt) : null,
        scheduledAt: probe.scheduledAt ? admin.firestore.Timestamp.fromDate(probe.scheduledAt) : null,
        viewerSignal: probe.viewerSignal ?? null,
        ingestConfidence: confidence,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        sources,
    };
}

function collectGroundingSources(
    church: Record<string, unknown>,
    summary: Record<string, unknown>,
    liveState: Record<string, unknown>
): GroundingSource[] {
    const sources: GroundingSource[] = [];

    if (typeof church.name === "string") {
        sources.push({
            id: "church-profile",
            type: "verifiedMetadata",
            title: "Church profile",
            detail: "Canonical AMEN church metadata.",
            verified: church.verificationStatus === "verified",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    if (typeof church.website === "string" && church.website.length > 0) {
        sources.push({
            id: "official-website",
            type: "officialWebsite",
            title: "Official church website",
            url: church.website,
            verified: church.officialWebsiteVerified === true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    if (Object.keys(summary).length > 0) {
        sources.push({
            id: "experience-summary",
            type: "adminProvided",
            title: "Church experience summary",
            detail: "Admin-provided or approved summary fields.",
            verified: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    if (Object.keys(liveState).length > 0) {
        sources.push({
            id: "live-state",
            type: "livestream",
            title: "Church live state",
            detail: "Current livestream state metadata.",
            verified: liveState.confidenceLevel === "verified",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    return sources;
}

function composeGroundedAnswer(
    question: string,
    church: Record<string, unknown>,
    summary: Record<string, unknown>,
    liveState: Record<string, unknown>
): string {
    const lower = question.toLowerCase();
    if (lower.includes("livestream")) {
        return typeof liveState.title === "string"
            ? `${liveState.title} ${typeof liveState.description === "string" ? liveState.description : ""}`.trim()
            : "I do not have enough verified information yet.";
    }

    const parts = [
        typeof church.name === "string" ? church.name : "This church",
        typeof summary.firstTimeFlow === "string" ? summary.firstTimeFlow : null,
        typeof summary.accessibility === "string" ? `Accessibility: ${summary.accessibility}` : null,
        typeof summary.parking === "string" ? `Parking: ${summary.parking}` : null,
    ].filter((value): value is string => Boolean(value && value.trim()));

    return parts.join(" ");
}

export const submitChurchVerificationRequest = onCall({region: "us-central1"}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const churchId = typeof data.churchId === "string" ? data.churchId : "";
    const contactEmail = typeof data.contactEmail === "string" ? data.contactEmail.trim() : "";

    if (!churchId || !contactEmail) {
        throw new HttpsError("invalid-argument", "churchId and contactEmail are required.");
    }

    const requestId = `${churchId}_${uid}`;
    await db.collection("church_verification_requests").doc(requestId).set({
        churchId,
        requestedBy: uid,
        contactEmail,
        claimedDomain: typeof data.claimedDomain === "string" ? data.claimedDomain : null,
        websiteProofURL: typeof data.websiteProofURL === "string" ? data.websiteProofURL : null,
        livestreamProofURL: typeof data.livestreamProofURL === "string" ? data.livestreamProofURL : null,
        notes: typeof data.notes === "string" ? data.notes : null,
        status: "pending",
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    await db.collection("churches").doc(churchId).set({
        verificationStatus: "pending",
        ownershipClaimed: true,
    }, {merge: true});

    return {success: true, requestId};
});

export const submitChurchProfileUpdate = onCall({region: "us-central1"}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const churchId = typeof data.churchId === "string" ? data.churchId : "";
    if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

    await assertChurchAccess(uid, churchId, ["owner", "admin", "editor"]);

    await db.collection("church_admin_edits").add({
        churchId,
        payload: {
            displayDescription: data.displayDescription ?? null,
            serviceTimes: Array.isArray(data.serviceTimes) ? data.serviceTimes : [],
            livestreamURL: data.livestreamURL ?? null,
            accessibilityInfo: Array.isArray(data.accessibilityInfo) ? data.accessibilityInfo : [],
            parkingInfo: data.parkingInfo ?? null,
            ministries: Array.isArray(data.ministries) ? data.ministries : [],
            events: Array.isArray(data.events) ? data.events : [],
            prayerNights: Array.isArray(data.prayerNights) ? data.prayerNights : [],
            firstTimeVisitorInfo: data.firstTimeVisitorInfo ?? null,
        },
        submittedBy: uid,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {success: true};
});

export const reviewChurchModerationItem = onCall({region: "us-central1"}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const queueItemId = typeof data.queueItemId === "string" ? data.queueItemId : "";
    const decision = typeof data.decision === "string" ? data.decision : "";
    if (!queueItemId || !decision) throw new HttpsError("invalid-argument", "queueItemId and decision are required.");

    await db.collection("moderation_queue").doc(queueItemId).set({
        moderationState: decision,
        moderationReasons: Array.isArray(data.reasons) ? data.reasons : [],
        reviewedBy: uid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        history: admin.firestore.FieldValue.arrayUnion({
            action: "review",
            decision,
            reviewerNote: typeof data.reviewerNote === "string" ? data.reviewerNote : null,
            actorId: uid,
            at: admin.firestore.FieldValue.serverTimestamp(),
        }),
    }, {merge: true});

    return {success: true};
});

export const refreshChurchLivestreamState = onCall({region: "us-central1"}, async (request) => {
    requireAuth(request);
    const churchId = typeof request.data?.churchId === "string" ? request.data.churchId : "";
    if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

    const church = (await db.collection("churches").doc(churchId).get()).data() ?? {};
    const probe = buildLivestreamRecord({
        provider: "embedded",
        title: typeof church.name === "string" ? `${church.name} livestream` : "Church livestream",
        streamUrl: typeof church.livestreamURL === "string" ? church.livestreamURL : "",
        thumbnailUrl: typeof church.thumbnailUrl === "string" ? church.thumbnailUrl : null,
        providerConfirmedLive: false,
        websiteConfirmed: church.officialWebsiteVerified === true,
    });

    await db.collection("churches").doc(churchId).collection("livestreams").doc("primary").set(probe, {merge: true});
    await db.collection("churches").doc(churchId).collection("live_state").doc("current").set({
        state: probe.liveNow ? "live" : "unknown",
        title: probe.liveNow ? "Live nearby" : "Not confirmed yet",
        description: probe.liveNow ? "Provider metadata indicates an active livestream." : "Live state could not be fully confirmed.",
        livestreamUrl: probe.streamUrl,
        confidence: probe.ingestConfidence,
        confidenceLevel: levelForConfidence(probe.ingestConfidence),
        sources: probe.sources,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {success: true};
});

export const generateGroundedChurchAnswer = onCall({region: "us-central1"}, async (request) => {
    requireAuth(request);
    const churchId = typeof request.data?.churchId === "string" ? request.data.churchId : "";
    const question = typeof request.data?.question === "string" ? request.data.question : "";
    if (!churchId || !question) {
        throw new HttpsError("invalid-argument", "churchId and question are required.");
    }

    const [churchDoc, summaryDoc, liveStateDoc] = await Promise.all([
        db.collection("churches").doc(churchId).get(),
        db.collection("churches").doc(churchId).collection("experience_summary").doc("current").get(),
        db.collection("churches").doc(churchId).collection("live_state").doc("current").get(),
    ]);

    const church = churchDoc.data() ?? {};
    const summary = summaryDoc.data() ?? {};
    const liveState = liveStateDoc.data() ?? {};
    const sources = collectGroundingSources(church, summary, liveState);
    const confidence = Math.min(0.95, Math.max(0.15, (church.profileConfidence as number | undefined) ?? 0.2));
    const note = confidence < 0.35
        ? "This has not yet been confirmed by the church."
        : "This appears based on public church metadata.";

    if (sources.length === 0) {
        return {
            response: "I do not have enough verified information yet.",
            confidence: 0.1,
            confidenceLevel: "low",
            sources: [],
            note,
            fallbackMessage: "This appears based on public church metadata.",
        };
    }

    return {
        response: composeGroundedAnswer(question, church, summary, liveState),
        confidence,
        confidenceLevel: levelForConfidence(confidence),
        sources,
        note,
        fallbackMessage: confidence < 0.35 ? "This has not yet been confirmed by the church." : undefined,
    };
});

export const moderateChurchMediaUpload = onCall({region: "us-central1"}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const churchId = typeof data.churchId === "string" ? data.churchId : "";
    const type = typeof data.type === "string" ? data.type : "media";
    if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

    const evaluation = evaluateModeration({
        labels: Array.isArray(data.labels) ? data.labels.filter((value): value is string => typeof value === "string") : [],
        ocrText: typeof data.ocrText === "string" ? data.ocrText : undefined,
        captionText: typeof data.captionText === "string" ? data.captionText : undefined,
        uploadVelocity: typeof data.uploadVelocity === "number" ? data.uploadVelocity : undefined,
        impersonationSignal: typeof data.impersonationSignal === "number" ? data.impersonationSignal : undefined,
    });

    const itemId = `${churchId}_${Date.now()}`;
    await db.collection("moderation_queue").doc(itemId).set({
        type,
        source: typeof data.source === "string" ? data.source : "church_upload",
        churchId,
        uploadedBy: uid,
        moderationState: evaluation.moderationState,
        moderationReasons: evaluation.moderationReasons,
        aiScores: evaluation.aiScores,
        escalated: evaluation.escalated,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        history: [{
            action: "ingested",
            actorId: uid,
            at: admin.firestore.FieldValue.serverTimestamp(),
        }],
    }, {merge: true});

    return {success: true, itemId, ...evaluation};
});

export const onChurchVerificationReviewed = onDocumentCreated(
    {document: "church_verification_reviews/{reviewId}", region: "us-central1"},
    async (event) => {
        const review = event.data?.data();
        if (!review) return;

        const churchId = typeof review.churchId === "string" ? review.churchId : "";
        if (!churchId) return;

        const profileConfidence = scoreChurchProfile({
            verificationStatus: review.status,
            officialWebsiteVerified: review.officialWebsiteVerified === true,
            livestreamVerified: review.livestreamVerified === true,
            ownershipClaimed: true,
            approvedMediaCount: typeof review.approvedMediaCount === "number" ? review.approvedMediaCount : 0,
            serviceTimeCount: typeof review.serviceTimeCount === "number" ? review.serviceTimeCount : 0,
            hasAdminEdits: review.hasAdminEdits === true,
        });

        await db.collection("churches").doc(churchId).set({
            verificationStatus: review.status === "verified" ? "verified" : review.status === "rejected" ? "rejected" : "pending",
            verificationLevel: review.level === "trusted" ? "trusted" : review.level === "official" ? "official" : "basic",
            verifiedAt: review.status === "verified" ? admin.firestore.FieldValue.serverTimestamp() : null,
            verifiedBy: typeof review.reviewedBy === "string" ? review.reviewedBy : null,
            officialWebsiteVerified: review.officialWebsiteVerified === true,
            livestreamVerified: review.livestreamVerified === true,
            ownershipClaimed: true,
            moderationStatus: "approved",
            profileConfidence,
        }, {merge: true});
    }
);
