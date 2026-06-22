/**
 * validateUserAge.ts — Backend/functions/src/moderation
 * Callable: validateUserAge
 *
 * COPPA compliance gate for new Google/Apple SSO users.
 * Called immediately after profile creation; user cannot proceed until this resolves.
 *
 * Invariants:
 *  • Only the authenticated user can validate their own age
 *  • Under-13 users: account is deleted server-side (not client-side, to prevent bypass)
 *  • 13+ users: ageVerified=true, ageVerificationRequired=false stamped in user doc
 *  • Only the birth YEAR and age group are stored — no full DOB retained (privacy)
 *  • Region: us-east1
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface ValidateUserAgeInput {
    birthYear: number;
    birthMonth: number;
    birthDay: number;
}

interface ValidateUserAgeResult {
    allowed: boolean;
    reason: "coppa_under_13" | "age_verified";
    ageGroup: "under_13" | "13_to_17" | "18_plus" | null;
}

export const validateUserAge = functions.onCall({ enforceAppCheck: true, region: "us-east1" }, async (request): Promise<ValidateUserAgeResult> => {
        if (!request.auth) {
            throw new functions.HttpsError("unauthenticated", "Auth required");
        }

        const uid = request.auth.uid;
        const data = request.data as ValidateUserAgeInput;

        // Validate input
        const { birthYear, birthMonth, birthDay } = data;
        if (
            typeof birthYear !== "number" || birthYear < 1900 || birthYear > new Date().getFullYear() ||
            typeof birthMonth !== "number" || birthMonth < 1 || birthMonth > 12 ||
            typeof birthDay !== "number" || birthDay < 1 || birthDay > 31
        ) {
            throw new functions.HttpsError("invalid-argument", "Invalid date of birth");
        }

        // Compute age at today's date
        const today = new Date();
        let age = today.getFullYear() - birthYear;
        const monthDiff = today.getMonth() + 1 - birthMonth;
        if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDay)) {
            age--;
        }

        const db = admin.firestore();

        if (age < 13) {
            // COPPA: delete the account server-side to prevent bypass
            try {
                await admin.auth().deleteUser(uid);
                await db.collection("users").doc(uid).delete();
            } catch (err) {
                // Log but don't throw — the client still receives the denial
                console.error("[validateUserAge] Failed to delete under-13 account", uid, err);
            }

            return { allowed: false, reason: "coppa_under_13", ageGroup: "under_13" };
        }

        const ageGroup: ValidateUserAgeResult["ageGroup"] = age < 18 ? "13_to_17" : "18_plus";

        // Stamp age verification — store birth YEAR only (not full DOB)
        await db.collection("users").doc(uid).set(
            {
                ageVerified: true,
                ageVerificationRequired: false,
                ageGroup,
                birthYear,          // year only — no month/day retained
                ageVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
        );

        return { allowed: true, reason: "age_verified", ageGroup };
    }
);
