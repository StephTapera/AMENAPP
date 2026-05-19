import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

function requireAuth(request: CallableRequest): void {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
}

export const getDiscoverReason = onCall({ enforceAppCheck: true, timeoutSeconds: 15 }, async (request) => {
  requireAuth(request);
  const itemId = String(request.data?.itemId ?? "").trim();
  if (!itemId) throw new HttpsError("invalid-argument", "itemId is required.");

  const reason = String(request.data?.reasonHint ?? "").trim() || "This was recommended based on your recent Amen activity and Discover settings.";
  return { itemId, reason };
});
