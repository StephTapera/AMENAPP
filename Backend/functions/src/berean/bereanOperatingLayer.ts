import {onCall, HttpsError} from "firebase-functions/v2/https";

export const generateBereanOperatingResponse = onCall(
    {enforceAppCheck: true},
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        if (!request.app) {
            throw new HttpsError("unauthenticated", "App Check attestation required.");
        }
        throw new HttpsError("unavailable", "generateBereanOperatingResponse is not available in this build.");
    }
);
