import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const enforceCreatorEntitlement = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Auth required");
    }
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    const ownerID = context.auth.uid;
    const entitlementRef = admin.firestore().collection("creatorEntitlements").doc(ownerID);
    const entitlementSnap = await entitlementRef.get();

    if (!entitlementSnap.exists) {
        return { ok: true, premium: false };
    }

    return { ok: true, premium: entitlementSnap.data()?.isPremium ?? false };
});
