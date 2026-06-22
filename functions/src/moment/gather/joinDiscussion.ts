import { onCall } from "firebase-functions/v2/https";
import { makeGatherHandler, MOMENT_REGION } from "./shared";

export const momentJoinDiscussion = onCall(
  { region: MOMENT_REGION, enforceAppCheck: true },
  makeGatherHandler("joinDiscussion"),
);
