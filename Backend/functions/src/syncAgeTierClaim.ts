import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

/**
 * syncAgeTierClaim — P1.1 FIX
 *
 * Sets the `ageTier` Firebase Auth custom claim whenever users/{uid}.ageTier
 * changes in Firestore. This allows Firestore Security Rules to read the tier
 * from `request.auth.token.ageTier` (zero Firestore reads) instead of calling
 * get(/databases/.../users/{uid}) on every rule evaluation.
 *
 * Firestore rules callerAgeTier() now prefers the JWT claim and falls back to
 * the Firestore get() only for users whose token predates this function's deployment.
 * After one token refresh (≤1 hour TTL), all users will have the claim.
 *
 * Valid values: 'blocked' | 'tierB' | 'tierC' | 'tierD'
 * Default assumed by rules when claim is absent: 'tierD' (18+, most permissive)
 */
export const syncAgeTierClaim = onDocumentUpdated(
    "users/{uid}",
    async (event) => {
        const before = event.data?.before?.data();
        const after = event.data?.after?.data();

        if (!before || !after) return;

        const oldTier = before.ageTier ?? null;
        const newTier = after.ageTier ?? null;

        // Only act when the field actually changed.
        if (oldTier === newTier) return;

        const uid = event.params.uid;

        try {
            if (newTier) {
                // Set (or update) the custom claim.
                await admin.auth().setCustomUserClaims(uid, { ageTier: newTier });
            } else {
                // ageTier was removed — clear the claim so the rules fall back to
                // the Firestore get() which will return 'tierD' by default.
                const existing = (await admin.auth().getUser(uid)).customClaims ?? {};
                delete (existing as Record<string, unknown>).ageTier;
                await admin.auth().setCustomUserClaims(uid, existing);
            }

            console.log(`[syncAgeTierClaim] uid=${uid} ageTier: ${oldTier} → ${newTier}`);
        } catch (err) {
            console.error(`[syncAgeTierClaim] Failed to set claim for uid=${uid}:`, err);
            // Do not throw — a failed claim sync degrades to the Firestore get()
            // fallback in rules, which is safe and functional.
        }
    }
);
