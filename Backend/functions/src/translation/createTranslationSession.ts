import {onCall, HttpsError} from "firebase-functions/v2/https";
import {enforceAmenGuards, requireAuthAndAppCheck, saveGeneratedDraft, lightweightModeration} from "../amenAI/common";

export const createTranslationSession = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    await enforceAmenGuards({uid, taskType: "translate_content", featureFlag: "amenTranslationEnabled", killSwitch: "amenTranslationKillSwitch"});
    const sourceText = String(request.data?.text ?? "");
    const targetLanguageCode = String(request.data?.targetLanguageCode ?? "").trim();
    if (!sourceText || !targetLanguageCode) throw new HttpsError("invalid-argument", "text and targetLanguageCode required");

    const safe = lightweightModeration(sourceText);
    if (!safe.ok) throw new HttpsError("failed-precondition", "Input blocked by translation policy.");

    const {draftId} = await saveGeneratedDraft({uid, sourceSurface: "translation", taskType: "translate_content", outputType: "translation", body: sourceText, languageCode: String(request.data?.sourceLanguageCode ?? "auto"), targetLanguageCode});
    return {draftId};
});
