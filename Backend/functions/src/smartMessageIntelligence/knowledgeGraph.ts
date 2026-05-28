import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { SmartKnowledgeNode } from "./types";
import { stableId } from "./validators";

const db = admin.firestore();

export async function createKnowledgeNode(input: {
  uid: string;
  scope: "user" | "space";
  spaceId?: string;
  sourceType: string;
  sourceId: string;
  title: string;
  summary: string;
  scriptureRefs: string[];
  topics: string[];
}): Promise<SmartKnowledgeNode> {
  if (input.scope === "space" && !input.spaceId) {
    throw new HttpsError("invalid-argument", "spaceId is required for space memory.");
  }
  const now = Date.now();
  const id = stableId("knowledge", [input.scope, input.spaceId ?? input.uid, input.sourceType, input.sourceId, input.title]);
  const node: SmartKnowledgeNode = {
    id,
    ownerScope: input.scope,
    nodeType: input.scriptureRefs.length ? "scripture" : input.topics.length ? "topic" : "discussion",
    title: input.title,
    summary: input.summary.slice(0, 500),
    scriptureRefs: input.scriptureRefs,
    topics: input.topics,
    linkedMessageIds: input.sourceType === "message" ? [input.sourceId] : [],
    linkedThreadIds: input.sourceType === "thread" ? [input.sourceId] : [],
    linkedSpaceIds: input.spaceId ? [input.spaceId] : [],
    createdAt: now,
    updatedAt: now,
  };
  const ref = input.scope === "user"
    ? db.collection("users").doc(input.uid).collection("smartMessageMemory").doc(id)
    : db.collection("spaces").doc(input.spaceId!).collection("knowledgeGraph").doc("nodes").collection("nodes").doc(id);
  await ref.set({
    ...node,
    sourceType: input.sourceType,
    sourceId: input.sourceId,
    generatedBy: "smartMessageIntelligence",
    createdAtServer: admin.firestore.FieldValue.serverTimestamp(),
    updatedAtServer: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return node;
}
