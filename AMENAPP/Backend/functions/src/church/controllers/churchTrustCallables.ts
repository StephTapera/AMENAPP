import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {churchTrustRepository} from "../services/ChurchTrustRepository";
import {churchConfidenceEngine} from "../services/ChurchConfidenceEngine";
import {churchModerationEngine} from "../services/ChurchModerationEngine";
import {churchLivestreamIngestionService} from "../services/ChurchLivestreamIngestionService";
import {churchGroundingService} from "../services/ChurchGroundingService";

const db = admin.firestore();

function requireAuth(request: {auth?: {uid?: string}}): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return uid;
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
    await churchTrustRepository.verificationQueueRef(requestId).set({
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

    await churchTrustRepository.writeVerification(churchId, {
        verificationStatus: "pending",
        ownershipClaimed: true,
    });

    return {success: true, requestId};
});

export const submitChurchProfileUpdate = onCall({region: "us-central1"}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const churchId = typeof data.churchId === "string" ? data.churchId : "";
    if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

    try {
        await churchTrustRepository.assertChurchAccess(uid, churchId, ["owner", "admin", "editor"]);
    } catch {
        throw new HttpsError("permission-denied", "You are not assigned to this church.");
    }

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

    await churchTrustRepository.moderationQueueRef(queueItemId).set({
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

    const church = (await churchTrustRepository.churchRef(churchId).get()).data() ?? {};
    const probe = churchLivestreamIngestionService.buildRecord({
        provider: "embedded",
        title: typeof church.name === "string" ? `${church.name} livestream` : "Church livestream",
        streamUrl: typeof church.livestreamURL === "string" ? church.livestreamURL : "",
        thumbnailUrl: typeof church.thumbnailUrl === "string" ? church.thumbnailUrl : null,
        providerConfirmedLive: false,
        websiteConfirmed: church.officialWebsiteVerified === true,
    });

    await churchTrustRepository.writeLivestream(churchId, "primary", probe);
    await churchTrustRepository.churchRef(churchId).collection("live_state").doc("current").set({
        state: probe.liveNow ? "live" : "unknown",
        title: probe.liveNow ? "Live nearby" : "Not confirmed yet",
        description: probe.liveNow ? "Provider metadata indicates an active livestream." : "Live state could not be fully confirmed.",
        livestreamUrl: probe.streamUrl,
        confidence: probe.ingestConfidence,
        confidenceLevel: churchConfidenceEngine.levelForConfidence(probe.ingestConfidence),
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

    return churchGroundingService.answerChurchQuestion(churchId, question);
});

export const syncYouTubeChurchStreams = onCall({region: "us-central1"}, async (request) => {
    requireAuth(request);
    return {
        success: true,
        status: "stub",
        message: "Provider API sync should be connected here for verified YouTube church channels.",
    };
});

export const updateChurchLiveSignals = onCall({region: "us-central1"}, async (request) => {
    requireAuth(request);
    return {
        success: true,
        status: "stub",
        message: "Aggregate viewer signals, approved stream metadata, and recent admin updates here.",
    };
});

export const moderateChurchMediaUpload = onCall({region: "us-central1"}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const churchId = typeof data.churchId === "string" ? data.churchId : "";
    const type = typeof data.type === "string" ? data.type : "media";
    if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

    const evaluation = churchModerationEngine.evaluate({
        labels: Array.isArray(data.labels) ? data.labels.filter((value): value is string => typeof value === "string") : [],
        ocrText: typeof data.ocrText === "string" ? data.ocrText : undefined,
        captionText: typeof data.captionText === "string" ? data.captionText : undefined,
        uploadVelocity: typeof data.uploadVelocity === "number" ? data.uploadVelocity : undefined,
        impersonationSignal: typeof data.impersonationSignal === "number" ? data.impersonationSignal : undefined,
    });

    const itemId = `${churchId}_${Date.now()}`;
    await churchTrustRepository.writeModerationItem(itemId, {
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
    });

    return {success: true, itemId, ...evaluation};
});

export const onChurchVerificationReviewed = onDocumentCreated(
    {document: "church_verification_reviews/{reviewId}", region: "us-central1"},
    async (event) => {
        const review = event.data?.data();
        if (!review) return;

        const churchId = typeof review.churchId === "string" ? review.churchId : "";
        if (!churchId) return;

        const profileConfidence = churchConfidenceEngine.scoreChurchProfile({
            verificationStatus: review.status,
            officialWebsiteVerified: review.officialWebsiteVerified === true,
            livestreamVerified: review.livestreamVerified === true,
            ownershipClaimed: true,
            approvedMediaCount: typeof review.approvedMediaCount === "number" ? review.approvedMediaCount : 0,
            serviceTimeCount: typeof review.serviceTimeCount === "number" ? review.serviceTimeCount : 0,
            hasAdminEdits: review.hasAdminEdits === true,
        });

        await churchTrustRepository.writeVerification(churchId, {
            verificationStatus: review.status === "verified" ? "verified" : review.status === "rejected" ? "rejected" : "pending",
            verificationLevel: review.level === "trusted" ? "trusted" : review.level === "official" ? "official" : "basic",
            verifiedAt: review.status === "verified" ? admin.firestore.FieldValue.serverTimestamp() : null,
            verifiedBy: typeof review.reviewedBy === "string" ? review.reviewedBy : null,
            officialWebsiteVerified: review.officialWebsiteVerified === true,
            livestreamVerified: review.livestreamVerified === true,
            ownershipClaimed: true,
            moderationStatus: "approved",
            profileConfidence,
        });
    }
);
