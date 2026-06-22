import { onCall } from "firebase-functions/v2/https";
import { makeDeepenHandler, MOMENT_REGION } from "./shared";

export const momentSummarize = onCall(
  { region: MOMENT_REGION, enforceAppCheck: true },
  makeDeepenHandler("summarize"),
);
