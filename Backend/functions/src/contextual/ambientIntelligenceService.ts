import * as admin from "firebase-admin";
import type { ContextAction, BereanContextPayload } from "./bereanSelectionActions";

const db = () => admin.firestore();

export async function recordAmbientSuggestion(
  userId: string,
  action: ContextAction,
  payload: BereanContextPayload,
  suggestionLabels: string[]
): Promise<void> {
  if (suggestionLabels.length === 0) {
    return;
  }

  await db()
    .collection("users")
    .doc(userId)
    .collection("ambientSuggestions")
    .doc()
    .set({
      userId,
      sourceSurface: payload.sourceSurface,
      sourceId: payload.sourceId ?? "",
      contentType: payload.contentType,
      action,
      labels: suggestionLabels,
      state: "available",
      createdAt: admin.firestore.Timestamp.now(),
    });
}
