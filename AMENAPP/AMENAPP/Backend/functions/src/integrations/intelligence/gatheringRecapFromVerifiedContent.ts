// integrations/intelligence/gatheringRecapFromVerifiedContent.ts
// Berean AI: Recap only from host-verified content. No fabrication. No auto-share.
// User must confirm before any recap is stored or shared.

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { assertGatheringHost } from "../integrationCallableGuards";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";

const db = admin.firestore();

export const gatheringGenerateRecap = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringId = data["gatheringId"] as string | undefined;
  const verifiedContentId = data["verifiedContentId"] as string | undefined;

  if (!gatheringId || !verifiedContentId) return errorResponse("invalid-input");

  try {
    await assertGatheringHost(uid, gatheringId);

    // Require explicit consent record — no content is processed without host upload + consent
    const consentSnap = await db.collection("gatheringVerifiedContent").doc(verifiedContentId).get();
    if (!consentSnap.exists) return errorResponse("permission-denied");

    const consent = consentSnap.data() as {
      gatheringId: string; uploadedByUid: string;
      consentGranted: boolean; contentType: string;
    };

    if (consent.gatheringId !== gatheringId) return errorResponse("permission-denied");
    if (consent.uploadedByUid !== uid) return errorResponse("permission-denied");
    if (!consent.consentGranted) return errorResponse("permission-denied");

    // Returns an editable draft template. Production implementation would call Berean/OpenAI here.
    return {
      success: true,
      recap: {
        draft: `[Draft recap from your uploaded ${consent.contentType}]\n\nKey themes discussed:\n• \n\nScripture references:\n• \n\nPrayer requests & follow-ups:\n• `,
        isAIDraft: true,
        requiresHostReview: true,
        autoShareEnabled: false,
        verifiedContentId,
      },
    };
  } catch (e) {
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[gatheringGenerateRecap]", e);
    return errorResponse("unknown");
  }
});
