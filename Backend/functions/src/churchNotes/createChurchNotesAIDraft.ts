import {onCall, HttpsError} from "firebase-functions/v2/https";
import {requireAuthAndAppCheck} from "../amenAI/common";

export const createChurchNotesAIDraft = onCall({enforceAppCheck: true}, async (request) => {
    await requireAuthAndAppCheck(request.auth, request.app);
    throw new HttpsError(
        "failed-precondition",
        "Legacy client-supplied Church Notes AI drafts are disabled. Use the processing job review flow."
    );
});
