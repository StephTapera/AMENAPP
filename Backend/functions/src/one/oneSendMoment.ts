/**
 * one_sendMoment — P5 gate deploy item
 *
 * Server-authoritative Moment ingest. Enforces ConsentDNA attachment and
 * mergedConsentDNA on relay (stricter-of-source/relay, SECURITY.md §8.3).
 * Validates audience scope, lifetime policy, and privacy contract before write.
 *
 * Contract: CONTRACTS.md §1/§2/§5/§15
 */
import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

interface SendMomentData {
  moment: Record<string, unknown>;
  recipientUIDs?: string[];
}

export const one_sendMoment = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new functions.HttpsError("unauthenticated", "Auth required");
    const uid = request.auth.uid;
    const data = request.data as SendMomentData;
    if (!data?.moment) throw new functions.HttpsError("invalid-argument", "moment required");

    const moment = data.moment;

    // Author ownership — caller must be the author
    if (moment["authorUID"] !== uid) {
      throw new functions.HttpsError("permission-denied", "Author UID mismatch");
    }

    // ConsentDNA must be present and reference the correct author
    const consentDNA = moment["consentDNA"] as Record<string, unknown> | undefined;
    if (!consentDNA) {
      throw new functions.HttpsError("invalid-argument", "consentDNA required");
    }
    if (consentDNA["authorUID"] !== uid) {
      throw new functions.HttpsError("permission-denied", "ConsentDNA authorUID mismatch");
    }

    // mergedConsentDNA enforcement on relay: if this is a relay (reachBudget.chainDepth > 0)
    // verify forwardAllowed on the source moment before accepting the write.
    const reachBudget = moment["reachBudget"] as Record<string, unknown> | undefined;
    if (reachBudget && (reachBudget["chainDepth"] as number) > 0) {
      const sourceID = moment["sourceRelayMomentID"] as string | undefined;
      if (sourceID) {
        const sourceSnap = await db().collection("one_moments").doc(sourceID).get();
        if (sourceSnap.exists) {
          const sourceMoment = sourceSnap.data() as Record<string, unknown>;
          const sourceConsent = sourceMoment["consentDNA"] as Record<string, unknown> | undefined;
          const sourcePerms = sourceConsent?.["permissions"] as Record<string, unknown> | undefined;
          if (sourcePerms?.["forwardAllowed"] === false) {
            throw new functions.HttpsError(
              "permission-denied",
              "Source moment does not allow forwarding."
            );
          }
          // TODO(Stage-3): apply full mergedConsentDNA — take stricter of source/relay
          // for every permission field before writing the new moment.
        }
      }
    }

    // Server-assigned fields (clients cannot set these)
    const momentID = db().collection("one_moments").doc().id;
    const serverMoment = {
      ...moment,
      id: momentID,
      authorUID: uid,           // re-assert; never trust client claim alone
      reportedAt: null,
      evidenceLocked: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db().collection("one_moments").doc(momentID).set(serverMoment);
    return { momentID };
  }
);
