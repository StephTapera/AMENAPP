import {onCall} from "firebase-functions/v2/https";
import {requireAuthAndAppCheck} from "../amenAI/common";

export const extractKeyMoments = onCall({enforceAppCheck: true}, async (request) => {
    await requireAuthAndAppCheck(request.auth, request.app);
    return {moments: [] as Array<{atMs: number; label: string}>};
});
