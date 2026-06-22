import {HttpsError, onCall} from "firebase-functions/v2/https";
import {churchGroundingService} from "../church/services/ChurchGroundingService";

function requireAuth(request: {auth?: {uid?: string}}): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return uid;
}

export const generateBereanOperatingResponse = onCall({region: "us-central1"}, async (request) => {
    requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const churchId = typeof data.churchId === "string" ? data.churchId : "";
    const question = typeof data.question === "string" ? data.question : "";

    if (!question) {
        throw new HttpsError("invalid-argument", "question is required.");
    }

    if (!churchId) {
        return {
            response: "I do not have enough verified information yet.",
            confidence: 0.1,
            confidenceLevel: "low",
            sources: [],
            note: "Not confirmed yet",
            fallbackMessage: "This appears based on public church metadata.",
        };
    }

    return churchGroundingService.answerChurchQuestion(churchId, question);
});
