import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";

const db = admin.firestore();
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const openaiApiKey = defineSecret("OPENAI_API_KEY");
const HAIKU_MODEL = "claude-haiku-4-5-20251001";
const EMBEDDING_MODEL = "text-embedding-3-small";
const TRANSCRIPTION_MODEL = "whisper-1";

function requireUser(request: { auth?: { uid: string }; app?: unknown }): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");
  return request.auth.uid;
}

function asString(value: unknown, maxLength: number, field: string, required = false): string | undefined {
  if (value === undefined || value === null) {
    if (required) throw new HttpsError("invalid-argument", `${field} is required.`);
    return undefined;
  }
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be a string.`);
  const trimmed = value.trim();
  if (required && !trimmed) throw new HttpsError("invalid-argument", `${field} is required.`);
  if (trimmed.length > maxLength) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return trimmed;
}

function requiredString(value: unknown, maxLength: number, field: string): string {
  const result = asString(value, maxLength, field, true);
  if (!result) throw new HttpsError("invalid-argument", `${field} is required.`);
  return result;
}

function now() {
  return admin.firestore.Timestamp.now();
}

function ownerPath(uid: string, collection: string, id: string) {
  return db.collection("users").doc(uid).collection(collection).doc(id);
}

function contentPath(contentId: string) {
  return db.collection("content").doc(contentId);
}

function safeLimit(value: unknown, fallback = 20, max = 50): number {
  return Math.min(Math.max(Number(value ?? fallback), 1), max);
}

function parseScheduledAt(value: string): FirebaseFirestore.Timestamp {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new HttpsError("invalid-argument", "scheduledAt must be an ISO date.");
  return admin.firestore.Timestamp.fromDate(date);
}

async function callAnthropic(apiKey: string, prompt: string, maxTokens = 500): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: HAIKU_MODEL,
      max_tokens: maxTokens,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!response.ok) {
    const error = await response.text();
    throw new HttpsError("internal", `Anthropic error: ${error.slice(0, 160)}`);
  }
  const data = await response.json() as { content?: Array<{ type: string; text: string }> };
  return data.content?.find((part) => part.type === "text")?.text.trim() ?? "";
}

async function callOpenAIEmbedding(apiKey: string, input: string): Promise<number[]> {
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input,
    }),
  });
  if (!response.ok) {
    const error = await response.text();
    throw new HttpsError("internal", `OpenAI embeddings error: ${error.slice(0, 160)}`);
  }
  const data = await response.json() as { data?: Array<{ embedding: number[] }> };
  return data.data?.[0]?.embedding ?? [];
}

async function callOpenAITranscription(apiKey: string, storagePath: string, mediaType: string): Promise<{ text: string; language: string }> {
  const [buffer] = await admin.storage().bucket().file(storagePath).download();
  const FormData = (await import("form-data")).default;
  const axios = (await import("axios")).default;
  const form = new FormData();
  const extension = mediaType === "audio" ? "m4a" : "mp4";
  form.append("file", buffer, {
    filename: `amen-media.${extension}`,
    contentType: mediaType === "audio" ? "audio/m4a" : "video/mp4",
  });
  form.append("model", TRANSCRIPTION_MODEL);
  form.append("response_format", "verbose_json");

  const response = await axios.post("https://api.openai.com/v1/audio/transcriptions", form, {
    headers: { Authorization: `Bearer ${apiKey}`, ...form.getHeaders() },
    timeout: 120_000,
  });
  return {
    text: String(response.data?.text ?? "").trim(),
    language: String(response.data?.language ?? "en"),
  };
}

function buildCaptionSegments(transcript: string): Array<Record<string, unknown>> {
  const sentences = transcript
    .replace(/\s+/g, " ")
    .split(/(?<=[.!?])\s+/)
    .map((part) => part.trim())
    .filter(Boolean)
    .slice(0, 200);
  let cursor = 0;
  return sentences.map((text, index) => {
    const duration = Math.max(2, Math.min(8, Math.ceil(text.length / 22)));
    const segment = {
      id: `caption-${index + 1}`,
      startTime: cursor,
      endTime: cursor + duration,
      text,
    };
    cursor += duration;
    return segment;
  });
}

async function requireOwnedMedia(uid: string, mediaId: string) {
  const mediaRef = ownerPath(uid, "media", mediaId);
  const media = await mediaRef.get();
  if (!media.exists || media.get("ownerId") !== uid) throw new HttpsError("not-found", "Media not found.");
  return { mediaRef, media };
}

async function getUniversalMediaTranscript(uid: string, mediaId: string): Promise<string> {
  const transcript = await ownerPath(uid, "media", mediaId).collection("transcriptTracks").doc("default").get();
  const text = String(transcript.get("text") ?? "").trim();
  if (!text) throw new HttpsError("failed-precondition", "Transcript is not ready.");
  return text;
}

async function requireContentOwner(uid: string, contentId: string) {
  const snapshot = await contentPath(contentId).get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Content not found.");
  if (snapshot.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the owner can perform this action.");
  return snapshot;
}

async function requireContentReadable(uid: string, contentId: string) {
  const snapshot = await contentPath(contentId).get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Content not found.");
  const isOwner = snapshot.get("ownerId") === uid;
  const isPublicApproved =
    snapshot.get("visibility") === "public" &&
    snapshot.get("publishState") === "published" &&
    snapshot.get("moderationState.status") === "approved";
  if (!isOwner && !isPublicApproved) {
    throw new HttpsError("permission-denied", "You cannot access this content.");
  }
  return snapshot;
}

async function requireCommunityWriter(uid: string, communityId: string) {
  const communityRef = db.collection("communities").doc(communityId);
  const community = await communityRef.get();
  if (!community.exists) throw new HttpsError("not-found", "Community not found.");
  const member = await communityRef.collection("members").doc(uid).get();
  const isAdmin = Array.isArray(community.get("adminIds")) && community.get("adminIds").includes(uid);
  const isCreator = community.get("creatorId") === uid;
  if (!isAdmin && !isCreator && !member.exists) throw new HttpsError("permission-denied", "Community membership required.");
  if (member.exists && member.get("status") === "banned") throw new HttpsError("permission-denied", "Banned users cannot post.");
  return communityRef;
}

export const createMediaUploadSession = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const mediaType = requiredString(data.type, 20, "type");
  if (!["image", "video", "audio"].includes(mediaType)) throw new HttpsError("invalid-argument", "Invalid media type.");

  const mediaId = db.collection("_").doc().id;
  const originalPath = `users/${uid}/media/${mediaId}/original`;
  const thumbnailPath = `users/${uid}/media/${mediaId}/thumbnails/cover`;
  const timestamp = now();

  await ownerPath(uid, "media", mediaId).set({
    id: mediaId,
    ownerId: uid,
    type: mediaType,
    storagePath: originalPath,
    thumbnailPath,
    uploadState: "created",
    processingState: "waitingForUpload",
    moderationState: { status: "pending" },
    transcriptStatus: "notRequested",
    captionStatus: "notRequested",
    createdAt: timestamp,
    updatedAt: timestamp,
  });

  return { success: true, mediaId, storagePath: originalPath, thumbnailPath };
});

export const finalizeMediaUpload = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const mediaId = requiredString(data.mediaId, 120, "mediaId");
  const width = typeof data.width === "number" ? data.width : null;
  const height = typeof data.height === "number" ? data.height : null;
  const duration = typeof data.duration === "number" ? data.duration : null;

  const ref = ownerPath(uid, "media", mediaId);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.get("ownerId") !== uid) throw new HttpsError("not-found", "Media upload not found.");

  await ref.update({
    width,
    height,
    duration,
    uploadState: "finalized",
    processingState: "queued",
    updatedAt: now(),
  });

  return { success: true, mediaId, processingState: "queued", moderationStatus: "pending" };
});

export const createNote = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const noteId = db.collection("notes").doc().id;
  const timestamp = now();
  const title = asString(data.title, 180, "title") ?? "Untitled note";

  await db.collection("notes").doc(noteId).set({
    id: noteId,
    ownerId: uid,
    title,
    visibility: "private",
    collaborators: [],
    aiSummary: null,
    moderationState: { status: "pending" },
    createdAt: timestamp,
    updatedAt: timestamp,
  });
  await ownerPath(uid, "noteIndex", noteId).set({ noteId, title, updatedAt: timestamp });

  return { success: true, noteId };
});

export const updateNoteBlock = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const noteId = requiredString(data.noteId, 120, "noteId");
  const blockId = asString(data.blockId, 120, "blockId") ?? db.collection("_").doc().id;
  const noteRef = db.collection("notes").doc(noteId);
  const note = await noteRef.get();
  if (!note.exists || note.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the note owner can edit blocks.");

  await noteRef.collection("blocks").doc(blockId).set({
    id: blockId,
    noteId,
    ownerId: uid,
    type: asString(data.type, 40, "type") ?? "text",
    text: asString(data.text, 12000, "text") ?? "",
    order: typeof data.order === "number" ? data.order : 0,
    updatedAt: now(),
  }, { merge: true });
  await noteRef.update({ updatedAt: now() });

  return { success: true, noteId, blockId };
});

export const saveDesignProject = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const designId = asString(data.designId, 120, "designId") ?? db.collection("_").doc().id;
  const timestamp = now();

  await ownerPath(uid, "designs", designId).set({
    id: designId,
    ownerId: uid,
    title: asString(data.title, 180, "title") ?? "Untitled design",
    templateId: asString(data.templateId, 120, "templateId"),
    payload: typeof data.payload === "object" && data.payload !== null ? data.payload : {},
    exportMetadata: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  }, { merge: true });

  return { success: true, designId };
});

export const exportDesignImageMetadata = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const designId = requiredString(data.designId, 120, "designId");
  const exportPath = requiredString(data.storagePath, 1024, "storagePath");
  if (!exportPath.startsWith(`users/${uid}/designs/${designId}/`)) {
    throw new HttpsError("permission-denied", "Design export path must belong to the owner.");
  }

  await ownerPath(uid, "designs", designId).update({
    exportMetadata: {
      storagePath: exportPath,
      width: typeof data.width === "number" ? data.width : null,
      height: typeof data.height === "number" ? data.height : null,
      exportedAt: now(),
    },
    updatedAt: now(),
  });

  return { success: true, designId, storagePath: exportPath };
});

export const createCommunity = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const communityId = db.collection("communities").doc().id;
  const timestamp = now();
  const type = asString(data.type, 40, "type") ?? "publicTopic";
  const allowedTypes = ["church", "creator", "studyGroup", "classGroup", "projectGroup", "privateCircle", "publicTopic"];
  if (!allowedTypes.includes(type)) throw new HttpsError("invalid-argument", "Invalid community type.");

  const batch = db.batch();
  const communityRef = db.collection("communities").doc(communityId);
  batch.set(communityRef, {
    id: communityId,
    creatorId: uid,
    adminIds: [uid],
    name: requiredString(data.name, 120, "name"),
    description: asString(data.description, 500, "description") ?? "",
    type,
    isPrivate: data.isPrivate === true,
    memberCount: 1,
    postCount: 0,
    moderationStatus: "approved",
    safetyStatus: "clear",
    createdAt: timestamp,
    updatedAt: timestamp,
  });
  batch.set(communityRef.collection("members").doc(uid), {
    uid,
    role: "owner",
    status: "active",
    joinedAt: timestamp,
  });
  await batch.commit();

  return { success: true, communityId };
});

export const getCommunityFeed = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const communityId = requiredString(data.communityId, 120, "communityId");
  const communityRef = db.collection("communities").doc(communityId);
  const community = await communityRef.get();
  if (!community.exists) throw new HttpsError("not-found", "Community not found.");
  const isPrivate = community.get("isPrivate") === true;
  const isAdmin = Array.isArray(community.get("adminIds")) && community.get("adminIds").includes(uid);
  const isCreator = community.get("creatorId") === uid;
  const member = await communityRef.collection("members").doc(uid).get();
  if (isPrivate && !isAdmin && !isCreator && !member.exists) throw new HttpsError("permission-denied", "Community membership required.");

  const snapshot = await communityRef.collection("content")
    .where("publishState", "==", "published")
    .where("moderationState.status", "==", "approved")
    .orderBy("createdAt", "desc")
    .limit(safeLimit(data.limit))
    .get();

  return { success: true, items: snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })) };
});

export const scheduleContent = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const contentId = requiredString(data.contentId, 120, "contentId");
  const scheduledAt = requiredString(data.scheduledAt, 80, "scheduledAt");
  const scheduleId = db.collection("_").doc().id;
  await requireContentOwner(uid, contentId);

  await ownerPath(uid, "scheduledContent", scheduleId).set({
    id: scheduleId,
    ownerId: uid,
    contentId,
    scheduledAt: parseScheduledAt(scheduledAt),
    status: "scheduled",
    createdAt: now(),
    updatedAt: now(),
  });

  return { success: true, scheduleId };
});

export const publishScheduledContent = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const scheduleId = requiredString((request.data as Record<string, unknown>).scheduleId, 120, "scheduleId");
  const scheduleRef = ownerPath(uid, "scheduledContent", scheduleId);
  const schedule = await scheduleRef.get();
  if (!schedule.exists || schedule.get("ownerId") !== uid) throw new HttpsError("not-found", "Schedule not found.");
  if (schedule.get("status") !== "scheduled") throw new HttpsError("failed-precondition", "Schedule is not active.");

  const contentId = requiredString(schedule.get("contentId"), 120, "contentId");
  const content = await requireContentOwner(uid, contentId);
  if (content.get("moderationState.status") !== "approved") {
    throw new HttpsError("failed-precondition", "Scheduled content is not approved.");
  }

  const timestamp = now();
  const batch = db.batch();
  batch.update(contentPath(contentId), {
    publishState: "published",
    publishedAt: timestamp,
    updatedAt: timestamp,
  });
  batch.update(scheduleRef, {
    status: "published",
    publishedAt: timestamp,
    updatedAt: timestamp,
  });
  await batch.commit();

  return { success: true, contentId, scheduleId };
});

export const createCommunityPost = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const communityId = requiredString(data.communityId, 120, "communityId");
  const communityRef = await requireCommunityWriter(uid, communityId);
  const contentId = db.collection("content").doc().id;
  const timestamp = now();
  const title = asString(data.title, 180, "title");
  const text = requiredString(data.text, 30000, "text");

  const node = {
    id: contentId,
    ownerId: uid,
    author: { displayName: "Amen user" },
    type: "communityPost",
    visibility: "community",
    title,
    text,
    blocks: [],
    mediaRefs: [],
    collaborators: [],
    moderationState: { status: "pending" },
    aiMetadata: { usedAI: false },
    communityId,
    createdAt: timestamp,
    updatedAt: timestamp,
    saveEligible: true,
    shareEligible: true,
    publishState: "published",
  };

  const batch = db.batch();
  batch.set(contentPath(contentId), node);
  batch.set(communityRef.collection("content").doc(contentId), node);
  batch.update(communityRef, {
    postCount: admin.firestore.FieldValue.increment(1),
    updatedAt: timestamp,
  });
  await batch.commit();

  return { success: true, contentId, moderationStatus: "pending" };
});

export const createReply = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const contentId = requiredString(data.contentId, 120, "contentId");
  const body = requiredString(data.body, 4000, "body");
  const parentReplyId = asString(data.parentReplyId, 120, "parentReplyId");
  await requireContentReadable(uid, contentId);

  const replyRef = contentPath(contentId).collection("replies").doc();
  await replyRef.set({
    id: replyRef.id,
    contentId,
    parentReplyId: parentReplyId ?? null,
    ownerId: uid,
    body,
    moderationState: { status: "pending" },
    deletedAt: null,
    createdAt: now(),
    updatedAt: now(),
  });

  return { success: true, replyId: replyRef.id, moderationStatus: "pending" };
});

export const summarizeThread = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const contentId = requiredString((request.data as Record<string, unknown>).contentId, 120, "contentId");
  const content = await requireContentReadable(uid, contentId);
  const replies = await contentPath(contentId).collection("replies")
    .where("moderationState.status", "==", "approved")
    .orderBy("createdAt", "asc")
    .limit(50)
    .get();
  const replyText = replies.docs
    .map((doc) => String(doc.get("body") ?? "").trim())
    .filter(Boolean)
    .slice(0, 50)
    .map((body, index) => `${index + 1}. ${body}`)
    .join("\n");
  const sourceText = [
    `Content title: ${content.get("title") ?? ""}`,
    `Content body: ${content.get("text") ?? ""}`,
    replyText ? `Approved replies:\n${replyText}` : "Approved replies: none yet.",
  ].join("\n\n").slice(0, 12000);
  const summary = await callAnthropic(
    anthropicApiKey.value(),
    `Summarize this thread into the most useful points, open questions, and follow-up ideas. Keep it concise and neutral.\n\n${sourceText}`,
    700
  );
  const summaryRef = contentPath(contentId).collection("threadSummaries").doc();
  await summaryRef.set({
    id: summaryRef.id,
    contentId,
    ownerId: uid,
    summary,
    provider: "anthropic",
    model: HAIKU_MODEL,
    replyCount: replies.docs.length,
    createdAt: now(),
  });
  return { success: true, summaryId: summaryRef.id, summary };
});

export const saveThreadToNote = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const contentId = requiredString(data.contentId, 120, "contentId");
  const summary = asString(data.summary, 12000, "summary") ?? "";
  const content = await requireContentReadable(uid, contentId);
  const noteId = db.collection("notes").doc().id;
  const title = asString(content.get("title"), 180, "title") ?? "Saved thread";
  const timestamp = now();
  const body = [
    summary ? `Summary\n${summary}` : "",
    content.get("text") ? `Original\n${content.get("text")}` : "",
  ].filter(Boolean).join("\n\n");

  const noteRef = db.collection("notes").doc(noteId);
  const batch = db.batch();
  batch.set(noteRef, {
    id: noteId,
    ownerId: uid,
    title: `Thread: ${title}`.slice(0, 180),
    visibility: "private",
    collaborators: [],
    aiSummary: summary || null,
    sourceContentId: contentId,
    moderationState: { status: "pending" },
    createdAt: timestamp,
    updatedAt: timestamp,
  });
  batch.set(noteRef.collection("blocks").doc("thread-summary"), {
    id: "thread-summary",
    noteId,
    ownerId: uid,
    type: "aiSummary",
    text: body || "Saved thread",
    order: 0,
    updatedAt: timestamp,
  });
  batch.set(ownerPath(uid, "noteIndex", noteId), {
    noteId,
    title: `Thread: ${title}`.slice(0, 180),
    sourceContentId: contentId,
    updatedAt: timestamp,
  });
  await batch.commit();
  return { success: true, noteId };
});

export const convertNoteToPost = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const noteId = requiredString((request.data as Record<string, unknown>).noteId, 120, "noteId");
  const note = await db.collection("notes").doc(noteId).get();
  if (!note.exists || note.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the note owner can convert it.");

  const draftId = db.collection("_").doc().id;
  const title = asString(note.get("title"), 180, "title") ?? "Untitled note";
  await ownerPath(uid, "drafts", draftId).set({
    id: draftId,
    ownerId: uid,
    draftType: "noteToPost",
    intent: "textPost",
    contentType: "post",
    title,
    text: title,
    sourceNoteId: noteId,
    intendedVisibility: "private",
    syncState: "synced",
    createdAt: now(),
    updatedAt: now(),
  });

  return { success: true, draftId };
});

export const convertNoteToCarousel = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const noteId = requiredString((request.data as Record<string, unknown>).noteId, 120, "noteId");
  const note = await db.collection("notes").doc(noteId).get();
  if (!note.exists || note.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the note owner can convert it.");

  const draftId = db.collection("_").doc().id;
  await ownerPath(uid, "drafts", draftId).set({
    id: draftId,
    ownerId: uid,
    draftType: "noteToCarousel",
    intent: "carousel",
    contentType: "post",
    title: asString(note.get("title"), 180, "title") ?? "Carousel draft",
    text: asString(note.get("title"), 180, "title") ?? "",
    sourceNoteId: noteId,
    intendedVisibility: "private",
    syncState: "synced",
    createdAt: now(),
    updatedAt: now(),
  });

  return { success: true, draftId };
});

export const convertNoteToVideoScript = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const noteId = requiredString((request.data as Record<string, unknown>).noteId, 120, "noteId");
  const note = await db.collection("notes").doc(noteId).get();
  if (!note.exists || note.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the note owner can convert it.");

  const draftId = db.collection("_").doc().id;
  await ownerPath(uid, "drafts", draftId).set({
    id: draftId,
    ownerId: uid,
    draftType: "noteToVideoScript",
    intent: "videoPost",
    contentType: "video",
    title: asString(note.get("title"), 180, "title") ?? "Video script",
    text: asString(note.get("title"), 180, "title") ?? "",
    sourceNoteId: noteId,
    intendedVisibility: "private",
    syncState: "synced",
    createdAt: now(),
    updatedAt: now(),
  });

  return { success: true, draftId };
});

export const indexContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const contentId = requiredString((request.data as Record<string, unknown>).contentId, 120, "contentId");
  const content = await requireContentOwner(uid, contentId);
  if (content.get("visibility") !== "public" || content.get("publishState") !== "published" || content.get("moderationState.status") !== "approved") {
    throw new HttpsError("failed-precondition", "Only public approved content can be indexed.");
  }

  await db.collection("searchIndex").doc(contentId).set({
    id: contentId,
    ownerId: uid,
    type: content.get("type"),
    title: content.get("title") ?? null,
    text: content.get("text") ?? "",
    visibility: "public",
    moderationStatus: "approved",
    indexedAt: now(),
  });

  return { success: true, contentId };
});

export const processUploadedMedia = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const mediaId = requiredString((request.data as Record<string, unknown>).mediaId, 120, "mediaId");
  const { mediaRef, media } = await requireOwnedMedia(uid, mediaId);
  if (media.get("uploadState") !== "finalized") throw new HttpsError("failed-precondition", "Upload must be finalized first.");

  await mediaRef.update({
    processingState: "processing",
    processingStartedAt: now(),
    updatedAt: now(),
  });

  return { success: true, mediaId, processingState: "processing" };
});

export const generateVideoTranscript = onCall({ region: "us-central1", timeoutSeconds: 180, enforceAppCheck: true, secrets: [openaiApiKey] }, async (request) => {
  const uid = requireUser(request);
  const mediaId = requiredString((request.data as Record<string, unknown>).mediaId, 120, "mediaId");
  const { mediaRef, media } = await requireOwnedMedia(uid, mediaId);
  const mediaType = String(media.get("type") ?? "");
  if (!["video", "audio"].includes(mediaType)) throw new HttpsError("failed-precondition", "Only video or audio media can be transcribed.");
  const storagePath = requiredString(media.get("storagePath"), 1024, "storagePath");
  if (!storagePath.startsWith(`users/${uid}/media/${mediaId}/`)) {
    throw new HttpsError("permission-denied", "Media storage path does not belong to the owner.");
  }

  await mediaRef.update({ transcriptStatus: "processing", updatedAt: now() });
  try {
    const result = await callOpenAITranscription(openaiApiKey.value(), storagePath, mediaType);
    if (!result.text) throw new HttpsError("internal", "Provider returned an empty transcript.");
    const timestamp = now();
    await mediaRef.collection("transcriptTracks").doc("default").set({
      id: "default",
      mediaId,
      ownerId: uid,
      text: result.text,
      language: result.language,
      provider: "openai",
      model: TRANSCRIPTION_MODEL,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    await mediaRef.update({
      transcriptStatus: "ready",
      processingState: "transcriptReady",
      updatedAt: timestamp,
    });
    return { success: true, mediaId, transcriptStatus: "ready", language: result.language };
  } catch (error) {
    await mediaRef.update({
      transcriptStatus: "failed",
      transcriptFailureReason: error instanceof Error ? error.message.slice(0, 240) : "Transcript generation failed.",
      updatedAt: now(),
    });
    throw error;
  }
});

export const generateCaptions = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const mediaId = requiredString((request.data as Record<string, unknown>).mediaId, 120, "mediaId");
  const { mediaRef } = await requireOwnedMedia(uid, mediaId);
  const transcript = await getUniversalMediaTranscript(uid, mediaId);
  const segments = buildCaptionSegments(transcript);
  if (segments.length === 0) throw new HttpsError("failed-precondition", "Transcript is too short to caption.");
  const timestamp = now();
  await mediaRef.collection("captionTracks").doc("default").set({
    id: "default",
    mediaId,
    ownerId: uid,
    generatedTranscript: transcript,
    segments,
    provider: "amen-transcript-segmenter",
    createdAt: timestamp,
    updatedAt: timestamp,
  });
  await mediaRef.update({
    captionStatus: "ready",
    captionsGenerationState: "ready",
    updatedAt: timestamp,
  });
  return { success: true, mediaId, captionStatus: "ready", segmentCount: segments.length };
});

export const generateVideoChapters = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const mediaId = requiredString((request.data as Record<string, unknown>).mediaId, 120, "mediaId");
  const { mediaRef } = await requireOwnedMedia(uid, mediaId);
  const transcript = await getUniversalMediaTranscript(uid, mediaId);
  const chaptersText = await callAnthropic(
    anthropicApiKey.value(),
    `Create concise video chapters from this transcript. Return 3-8 lines in the format "Title - summary".\n\n${transcript.slice(0, 12000)}`,
    700
  );
  const chapters = chaptersText.split("\n").map((line, index) => ({
    id: `chapter-${index + 1}`,
    order: index,
    text: line.trim(),
  })).filter((chapter) => chapter.text);
  await mediaRef.update({
    chapters,
    chapterStatus: "ready",
    chapterProvider: "anthropic",
    chapterModel: HAIKU_MODEL,
    updatedAt: now(),
  });
  return { success: true, mediaId, chapterCount: chapters.length };
});

export const generateMediaSummary = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const mediaId = requiredString((request.data as Record<string, unknown>).mediaId, 120, "mediaId");
  const { mediaRef } = await requireOwnedMedia(uid, mediaId);
  const transcript = await getUniversalMediaTranscript(uid, mediaId);
  const summary = await callAnthropic(
    anthropicApiKey.value(),
    `Summarize this media transcript clearly. Include key ideas and any follow-up actions. Return only the summary.\n\n${transcript.slice(0, 12000)}`,
    700
  );
  await mediaRef.update({
    summary,
    summaryStatus: "ready",
    summaryProvider: "anthropic",
    summaryModel: HAIKU_MODEL,
    updatedAt: now(),
  });
  return { success: true, mediaId, summary };
});

async function runUniversalAIJob(
  uid: string,
  feature: string,
  text: string,
  instruction: string
): Promise<Record<string, unknown>> {
  const jobId = db.collection("_").doc().id;
  const jobRef = ownerPath(uid, "aiJobs", jobId);
  await jobRef.set({
    id: jobId,
    ownerId: uid,
    feature,
    inputPreview: text.slice(0, 280),
    status: "running",
    provider: "anthropic",
    model: HAIKU_MODEL,
    createdAt: now(),
    updatedAt: now(),
  });

  try {
    const output = await callAnthropic(anthropicApiKey.value(), `${instruction}\n\nInput:\n${text.slice(0, 12000)}`, 700);
    await jobRef.update({
      status: "completed",
      outputPreview: output.slice(0, 500),
      completedAt: now(),
      updatedAt: now(),
    });
    return {
      success: true,
      jobId,
      status: "completed",
      result: {
        text: output,
        aiMetadata: {
          usedAI: true,
          provider: "anthropic",
          model: HAIKU_MODEL,
          disclosureLabel: "AI-assisted draft",
          userAccepted: false,
        },
      },
    };
  } catch (error) {
    await jobRef.update({
      status: "failed",
      reason: error instanceof Error ? error.message.slice(0, 240) : "AI generation failed.",
      updatedAt: now(),
    });
    throw error;
  }
}

export const generateEmbeddings = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true, secrets: [openaiApiKey] }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const contentId = requiredString(data.contentId, 120, "contentId");
  const content = await requireContentOwner(uid, contentId);
  if (content.get("visibility") !== "public" || content.get("publishState") !== "published" || content.get("moderationState.status") !== "approved") {
    throw new HttpsError("failed-precondition", "Only public approved content can be embedded.");
  }
  const input = `${content.get("title") ?? ""}\n${content.get("text") ?? ""}`.trim();
  if (!input) throw new HttpsError("failed-precondition", "Content has no text to embed.");
  const embedding = await callOpenAIEmbedding(openaiApiKey.value(), input.slice(0, 8000));
  await db.collection("contentEmbeddings").doc(contentId).set({
    id: contentId,
    ownerId: uid,
    model: EMBEDDING_MODEL,
    dimensions: embedding.length,
    embedding,
    visibility: "public",
    moderationStatus: "approved",
    createdAt: now(),
    updatedAt: now(),
  });
  return { success: true, contentId, dimensions: embedding.length };
});

export const rewriteContent = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const text = requiredString((request.data as Record<string, unknown>).text, 12000, "text");
  return runUniversalAIJob(uid, "rewriteContent", text, "Rewrite this draft to be clearer, safer, calmer, and more natural. Return only the rewritten draft. Do not publish it.");
});

export const summarizeContent = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const text = requiredString((request.data as Record<string, unknown>).text, 12000, "text");
  return runUniversalAIJob(uid, "summarizeContent", text, "Summarize this content into a concise, useful summary. Return only the summary.");
});

export const translateContent = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const text = requiredString(data.text, 12000, "text");
  const targetLanguage = asString(data.targetLanguage, 80, "targetLanguage") ?? "English";
  return runUniversalAIJob(uid, "translateContent", text, `Translate this content into ${targetLanguage}. Preserve meaning and tone. Return only the translation.`);
});

export const generateAccessibilityAltText = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const text = requiredString((request.data as Record<string, unknown>).text, 12000, "text");
  return runUniversalAIJob(uid, "generateAccessibilityAltText", text, "Write concise accessibility alt text for the described media/content. Return only the alt text.");
});

export const generateVideoScript = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const text = requiredString((request.data as Record<string, unknown>).text, 12000, "text");
  return runUniversalAIJob(uid, "generateVideoScript", text, "Turn this idea into a short-form video script with hook, beats, and closing line. Return only the script.");
});

export const generateVoiceoverScript = onCall({ region: "us-central1", timeoutSeconds: 30, enforceAppCheck: true, secrets: [anthropicApiKey] }, async (request) => {
  const uid = requireUser(request);
  const text = requiredString((request.data as Record<string, unknown>).text, 12000, "text");
  return runUniversalAIJob(uid, "generateVoiceoverScript", text, "Turn this content into a natural voiceover script. Return only the voiceover script.");
});

// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const publishDueUniversalScheduledContent = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1", timeZone: "Etc/UTC" },
  async () => {
    // Idempotency: lock by 5-minute window
    const nowMs = Date.now();
    const windowMs = 5 * 60 * 1000;
    const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
    const lockRef = db.doc(`system/scheduledJobLocks/publishDueUniversalContent_${windowKey}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      if (snap.exists && snap.data()?.status === "completed") {
        return false;
      }
      tx.set(lockRef, {
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        windowKey,
        expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
      });
      return true;
    });

    if (!lockAcquired) {
      console.info("publishDueUniversalScheduledContent already completed this window, skipping", { windowKey });
      return;
    }

    try {
      const due = await db.collectionGroup("scheduledContent")
        .where("status", "==", "scheduled")
        .where("scheduledAt", "<=", now())
        .limit(50)
        .get();

      const batch = db.batch();
      let published = 0;
      let blocked = 0;

      for (const doc of due.docs) {
        const data = doc.data();
        const contentId = String(data.contentId ?? "");
        const ownerId = String(data.ownerId ?? "");
        if (!contentId || !ownerId) {
          batch.update(doc.ref, { status: "failed", failureReason: "missing_content_reference", updatedAt: now() });
          blocked += 1;
          continue;
        }

        const contentRef = contentPath(contentId);
        const content = await contentRef.get();
        if (!content.exists || content.get("ownerId") !== ownerId) {
          batch.update(doc.ref, { status: "failed", failureReason: "content_missing_or_owner_mismatch", updatedAt: now() });
          blocked += 1;
          continue;
        }

        if (content.get("moderationState.status") !== "approved") {
          batch.update(doc.ref, { status: "blocked", failureReason: "moderation_not_approved", updatedAt: now() });
          blocked += 1;
          continue;
        }

        const timestamp = now();
        batch.update(contentRef, { publishState: "published", publishedAt: timestamp, updatedAt: timestamp });
        batch.update(doc.ref, { status: "published", publishedAt: timestamp, updatedAt: timestamp });
        published += 1;
      }

      if (!due.empty) await batch.commit();
      console.info("publishDueUniversalScheduledContent", { published, blocked });

      await lockRef.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await lockRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw err;
    }
  }
);

export const processQueuedUniversalMedia = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1", timeZone: "Etc/UTC" },
  async () => {
    // Idempotency: lock by 5-minute window
    const nowMs = Date.now();
    const windowMs = 5 * 60 * 1000;
    const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
    const lockRef = db.doc(`system/scheduledJobLocks/processQueuedUniversalMedia_${windowKey}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      if (snap.exists && snap.data()?.status === "completed") {
        return false;
      }
      tx.set(lockRef, {
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        windowKey,
        expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
      });
      return true;
    });

    if (!lockAcquired) {
      console.info("processQueuedUniversalMedia already completed this window, skipping", { windowKey });
      return;
    }

    try {
      const queued = await db.collectionGroup("media")
        .where("processingState", "in", ["queued", "processing"])
        .limit(50)
        .get();

      const batch = db.batch();
      let completed = 0;

      for (const doc of queued.docs) {
        const mediaType = String(doc.get("type") ?? "unknown");
        const timestamp = now();
        batch.update(doc.ref, {
          processingState: "ready",
          transcriptStatus: mediaType === "video" || mediaType === "audio" ? "pending" : "notRequired",
          captionStatus: mediaType === "video" || mediaType === "audio" ? "pending" : "notRequired",
          chapterStatus: mediaType === "video" || mediaType === "audio" ? "pending" : "notRequired",
          summaryStatus: "pending",
          "moderationState.status": "pending",
          processedAt: timestamp,
          updatedAt: timestamp,
        });
        completed += 1;
      }

      if (!queued.empty) await batch.commit();
      console.info("processQueuedUniversalMedia", { completed });

      await lockRef.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await lockRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw err;
    }
  }
);
