import {onCall, HttpsError} from "firebase-functions/v2/https";
import {enforceAmenGuards, requireAuthAndAppCheck, saveGeneratedDraft} from "../amenAI/common";

export const startRealtimeTranscription = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    await enforceAmenGuards({uid, taskType: "captions", featureFlag: "amenLiveCaptionsEnabled", killSwitch: "amenLiveCaptionsKillSwitch"});

    const transcript = String(request.data?.transcript ?? "").trim();
    if (!transcript) throw new HttpsError("invalid-argument", "transcript required");

    const {draftId} = await saveGeneratedDraft({uid, sourceSurface: "media", taskType: "caption_track", outputType: "caption", body: transcript, languageCode: String(request.data?.languageCode ?? "en")});
    return {draftId, status: "draftReady"};
});
