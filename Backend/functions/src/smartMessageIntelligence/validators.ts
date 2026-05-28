import * as admin from "firebase-admin";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { SmartMessageAction, SmartMessageContext } from "./types";

const db = admin.firestore();

export const MAX_TEXT_LENGTH = 6000;

export function requireAuthAndAppCheck(request: CallableRequest): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!request.app) {
    throw new HttpsError("unauthenticated", "App Check required.");
  }
  return request.auth.uid;
}

export function sanitizeText(value: unknown, maxLength = MAX_TEXT_LENGTH): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Text is required.");
  }
  const text = Array.from(value)
    .map((character) => {
      const code = character.charCodeAt(0);
      return code < 32 && ![9, 10, 13].includes(code) ? " " : character;
    })
    .join("")
    .trim();
  if (!text) {
    throw new HttpsError("invalid-argument", "Text is required.");
  }
  if (text.length > maxLength) {
    throw new HttpsError("invalid-argument", `Text must be ${maxLength} characters or less.`);
  }
  return text;
}

export function requiredString(data: Record<string, unknown>, key: string): string {
  const value = data[key];
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${key} is required.`);
  }
  return value.trim();
}

export async function requireSpaceMember(uid: string, spaceId: string): Promise<void> {
  const memberRef = db.collection("spaces").doc(spaceId).collection("members").doc(uid);
  const [memberSnap, spaceSnap] = await Promise.all([
    memberRef.get(),
    db.collection("spaces").doc(spaceId).get(),
  ]);

  const status = String(memberSnap.data()?.status ?? "");
  const memberBySubcollection = memberSnap.exists && !["removed", "blocked", "left"].includes(status);
  const memberIds = spaceSnap.data()?.memberIds;
  const memberByArray = Array.isArray(memberIds) && memberIds.includes(uid);

  if (!memberBySubcollection && !memberByArray) {
    throw new HttpsError("permission-denied", "Space membership required.");
  }
}

export async function parseMessageContext(uid: string, data: Record<string, unknown>): Promise<SmartMessageContext> {
  const spaceId = requiredString(data, "spaceId");
  const threadId = requiredString(data, "threadId");
  const messageId = typeof data.messageId === "string" ? data.messageId.trim() : undefined;
  const text = sanitizeText(data.text);
  await requireSpaceMember(uid, spaceId);
  return { uid, spaceId, threadId, messageId, text };
}

export function stableId(prefix: string, parts: unknown[]): string {
  const source = parts.map((part) => String(part ?? "")).join("|");
  let hash = 0;
  for (let index = 0; index < source.length; index += 1) {
    hash = ((hash << 5) - hash + source.charCodeAt(index)) | 0;
  }
  return `${prefix}_${Math.abs(hash)}`;
}

export function dedupeActions(actions: SmartMessageAction[]): SmartMessageAction[] {
  const seen = new Set<string>();
  return actions.filter((action) => {
    const key = `${action.actionType}:${JSON.stringify(action.payload)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export async function writeEntities(
  spaceId: string,
  threadId: string,
  entities: Record<string, unknown>[]
): Promise<void> {
  if (!entities.length) return;
  const batch = db.batch();
  for (const entity of entities) {
    const id = String(entity.id);
    const ref = db.collection("spaces").doc(spaceId)
      .collection("smartThreads").doc(threadId)
      .collection("entities").doc(id);
    batch.set(ref, {
      ...entity,
      generatedBy: "smartMessageIntelligence",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAtServer: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await batch.commit();
}
