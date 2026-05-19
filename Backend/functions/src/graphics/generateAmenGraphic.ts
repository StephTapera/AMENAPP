import {onCall, HttpsError} from "firebase-functions/v2/https";
import {enforceAmenGuards, requireAuthAndAppCheck, saveGeneratedDraft, lightweightModeration} from "../amenAI/common";

export const generateAmenGraphic = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    await enforceAmenGuards({uid, taskType: "generate_graphic_prompt", featureFlag: "amenGraphicStudioEnabled", killSwitch: "amenGraphicGenerationKillSwitch"});
    const prompt = String(request.data?.prompt ?? "").trim();
    if (!prompt) throw new HttpsError("invalid-argument", "prompt required");
    const safe = lightweightModeration(prompt);
    if (!safe.ok) throw new HttpsError("failed-precondition", "Prompt blocked by safety policy.");

    const {draftId} = await saveGeneratedDraft({uid, sourceSurface: "graphic_studio", taskType: "generate_graphic_prompt", outputType: "image_prompt", body: prompt});
    return {draftId};
});
