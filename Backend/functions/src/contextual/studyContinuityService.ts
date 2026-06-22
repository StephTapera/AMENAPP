import * as admin from "firebase-admin";
import type { ContextAction, BereanContextPayload } from "./bereanSelectionActions";

const db = () => admin.firestore();

export async function recordStudyContinuity(
  userId: string,
  action: ContextAction,
  payload: BereanContextPayload,
  threadId: string
): Promise<void> {
  const now = admin.firestore.Timestamp.now();
  await db()
    .collection("users")
    .doc(userId)
    .collection("studyContinuity")
    .doc(threadId)
    .set(
      {
        userId,
        threadId,
        sourceSurface: payload.sourceSurface,
        sourceId: payload.sourceId ?? "",
        contentType: payload.contentType,
        scriptureReference: payload.scriptureReference ?? "",
        lastAction: action,
        updatedAt: now,
        createdAt: now,
      },
      { merge: true }
    );
}
