/**
 * one_activateLegacy — P5 gate deploy item
 *
 * Activates a legacy directive. Trustee-only — server validates that the
 * calling UID is in the directive's trustees array with canActivate=true.
 * Owner cannot self-activate; trustees verify before execution.
 *
 * Contract: CONTRACTS.md §11/§15
 */
import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

interface ActivateLegacyData { directiveID: string; }

export const one_activateLegacy = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new functions.HttpsError("unauthenticated", "Auth required");
    const uid = request.auth.uid;
    const data = request.data as ActivateLegacyData;
    if (!data?.directiveID) throw new functions.HttpsError("invalid-argument", "directiveID required");

    const ref = db().collection("one_legacy").doc(data.directiveID);
    const snap = await ref.get();
    if (!snap.exists) throw new functions.HttpsError("not-found", "Directive not found");

    const directive = snap.data() as Record<string, unknown>;

    // Owner cannot activate their own directive (trustees verify on behalf of owner)
    if (directive["ownerUID"] === uid) {
      throw new functions.HttpsError(
        "permission-denied",
        "The owner cannot activate their own legacy directive. A trustee must activate it."
      );
    }

    // Verify caller is a trustee with canActivate=true
    const trustees = (directive["trustees"] as Array<Record<string, unknown>>) ?? [];
    const callerTrustee = trustees.find(
      (t) => t["uid"] === uid && t["canActivate"] === true
    );
    if (!callerTrustee) {
      throw new functions.HttpsError(
        "permission-denied",
        "You are not authorized to activate this directive."
      );
    }

    // Already activated guard
    if (directive["activatedAt"]) {
      return { activated: true, alreadyActive: true };
    }

    await ref.update({
      activatedAt: admin.firestore.FieldValue.serverTimestamp(),
      activatedByUID: uid,
    });

    // TODO(Stage-3): trigger bequest delivery (time-release vault items to recipients)

    return { activated: true, alreadyActive: false };
  }
);
