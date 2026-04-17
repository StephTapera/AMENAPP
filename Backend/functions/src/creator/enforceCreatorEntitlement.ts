import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const enforceCreatorEntitlement = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    const ownerID = context.auth.uid;
    const entitlementRef = admin.firestore().collection("creatorEntitlements").doc(ownerID);
    const entitlementSnap = await entitlementRef.get();

    if (!entitlementSnap.exists) {
        return { ok: true, premium: false };
    }

    return { ok: true, premium: entitlementSnap.data()?.isPremium ?? false };
});
