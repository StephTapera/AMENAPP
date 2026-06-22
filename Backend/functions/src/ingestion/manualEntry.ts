import * as admin from "firebase-admin";
import type { Work, WorkLink, WorkType } from "./providers/types";

export interface ManualWorkInput {
  type?: WorkType;
  title?: string;
  subtitle?: string;
  description?: string;
  coverUrl?: string;
  publishedAt?: string | Date | FirebaseFirestore.Timestamp | null;
  links?: WorkLink[];
  topics?: string[];
}

function normalizePublishedAt(
  value: ManualWorkInput["publishedAt"]
): FirebaseFirestore.Timestamp | null {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : admin.firestore.Timestamp.fromDate(date);
}

function buildManualWork(creatorId: string, input: ManualWorkInput): Omit<Work, "id"> {
  const now = admin.firestore.Timestamp.now();
  const title = input.title?.trim();
  if (!title) throw new Error("title_required");

  return {
    creatorId,
    type: input.type ?? "article",
    title,
    subtitle: input.subtitle?.trim() || undefined,
    description: input.description?.trim() || undefined,
    coverUrl: input.coverUrl?.trim() || undefined,
    publishedAt: normalizePublishedAt(input.publishedAt),
    links: Array.isArray(input.links) ? input.links : [],
    topics: Array.isArray(input.topics) ? input.topics.slice(0, 12) : [],
    visibility: "private",
    reviewState: "draft",
    verifiedOwnership: true,
    ingestMode: "manual",
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ageTierRestriction: "all",
  };
}

export async function createManualWork(creatorId: string, input: ManualWorkInput): Promise<string> {
  const work = buildManualWork(creatorId, input);
  const ref = admin.firestore().collection("works").doc();
  await ref.set({ ...work, id: ref.id });
  return ref.id;
}

export async function updateManualWork(
  workId: string,
  creatorId: string,
  updates: Partial<ManualWorkInput>
): Promise<void> {
  const ref = admin.firestore().collection("works").doc(workId);
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error("work_not_found");
    const data = snap.data() as Work;
    if (data.creatorId !== creatorId) throw new Error("access_denied");
    if (data.ingestMode !== "manual") throw new Error("not_manual_work");

    const patch = buildManualWork(creatorId, { ...data, ...updates });
    tx.update(ref, {
      type: patch.type,
      title: patch.title,
      subtitle: patch.subtitle ?? null,
      description: patch.description ?? null,
      coverUrl: patch.coverUrl ?? null,
      publishedAt: patch.publishedAt,
      links: patch.links,
      topics: patch.topics,
      updatedAt: admin.firestore.Timestamp.now(),
    });
  });
}
