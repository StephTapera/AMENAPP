import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

function unavailableCallable(name: string) {
    return onCall(async () => {
        throw new HttpsError("unavailable", `${name} is not available in this build.`);
    });
}

export const submitChurchVerificationRequest = unavailableCallable("submitChurchVerificationRequest");
export const submitChurchProfileUpdate = unavailableCallable("submitChurchProfileUpdate");
export const reviewChurchModerationItem = unavailableCallable("reviewChurchModerationItem");
export const refreshChurchLivestreamState = unavailableCallable("refreshChurchLivestreamState");
export const generateGroundedChurchAnswer = unavailableCallable("generateGroundedChurchAnswer");
export const syncYouTubeChurchStreams = unavailableCallable("syncYouTubeChurchStreams");
export const updateChurchLiveSignals = unavailableCallable("updateChurchLiveSignals");
export const moderateChurchMediaUpload = unavailableCallable("moderateChurchMediaUpload");

export const onChurchVerificationReviewed = onDocumentWritten(
    "church_verification_requests/{requestId}",
    async () => undefined
);
