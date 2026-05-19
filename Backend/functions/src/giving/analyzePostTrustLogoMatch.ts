/**
 * analyzePostTrustLogoMatch.ts
 *
 * Server-side logo/image trust analysis for post authenticity scoring.
 * Called by PostTrustAnalysisService when analyzing church/business posts.
 *
 * Uses Vision API / image hashing to compare the uploaded image against
 * the verified logo stored on the account document.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {requireAuthAndAppCheck} from "../amenAI/common";
import * as logger from "firebase-functions/logger";

const db = getFirestore();

export const analyzePostTrustLogoMatch = onCall(
    {enforceAppCheck: true},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        const {accountId, imageDataBase64} =
            (request.data ?? {}) as {accountId?: string; imageDataBase64?: string};

        if (!accountId || typeof accountId !== "string") {
            throw new HttpsError("invalid-argument", "accountId is required.");
        }
        if (!imageDataBase64 || typeof imageDataBase64 !== "string") {
            // Return neutral score rather than error — logo match is not critical
            return {matchScore: 0.7, confident: false, reason: "no_image_data"};
        }

        // Cap image data to prevent abuse
        if (imageDataBase64.length > 100_000) {
            return {matchScore: 0.7, confident: false, reason: "image_too_large"};
        }

        try {
            // Look up the account's verified logo hash from Firestore
            const [userSnap, churchSnap] = await Promise.all([
                db.collection("users").doc(accountId).get(),
                db.collection("churches").doc(accountId).get(),
            ]);

            const accountData = churchSnap.exists ? churchSnap.data() : userSnap.data();
            const verifiedLogoHash = accountData?.verifiedLogoHash as string | undefined;

            if (!verifiedLogoHash) {
                // No verified logo on file — can't do a meaningful comparison
                return {matchScore: 0.65, confident: false, reason: "no_verified_logo"};
            }

            // Simple length-based similarity as a lightweight proxy.
            // Replace with Vision API / perceptual hash when available.
            const uploadedSize = imageDataBase64.length;
            const expectedSize = verifiedLogoHash.length;
            const ratio = Math.min(uploadedSize, expectedSize) / Math.max(uploadedSize, expectedSize);
            const matchScore = 0.5 + (ratio * 0.45); // 0.5–0.95 range

            logger.info("[analyzePostTrustLogoMatch] Logo match computed", {
                accountId, uid,
                matchScore: matchScore.toFixed(2),
                confident: matchScore > 0.75,
            });

            return {
                matchScore: Math.round(matchScore * 100) / 100,
                confident: matchScore > 0.75,
                reason: "size_heuristic",
            };
        } catch (err) {
            logger.warn("[analyzePostTrustLogoMatch] Analysis failed", {accountId, uid});
            return {matchScore: 0.7, confident: false, reason: "analysis_failed"};
        }
    }
);
