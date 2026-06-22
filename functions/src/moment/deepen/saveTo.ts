import { onCall } from "firebase-functions/v2/https";
import { makeDeepenHandler, MOMENT_REGION } from "./shared";

export const momentSaveTo = onCall(
  { region: MOMENT_REGION, enforceAppCheck: true },
  makeDeepenHandler("saveTo"),
);
