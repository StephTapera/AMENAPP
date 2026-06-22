const {onDocumentCreated, onDocumentUpdated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const db = admin.firestore();

function buildMediaMetaDoc(postId, authorId, item) {
  const generationStatus = item.processingStatus || {};
  return {
    postId,
    authorId,
    mediaId: item.id,
    type: item.type,
    width: item.width || null,
    height: item.height || null,
    duration: item.duration || null,
    thumbnailURL: item.thumbnailURL || null,
    previewURL: item.previewURL || item.thumbnailURL || null,
    originalURL: item.originalURL || item.url,
    featuredFrameTime: item.featuredFrameTime || null,
    featuredFrameIndex: item.frameCaptionMetadata?.frameIndex ?? null,
    frameCaption: item.frameCaptionMetadata?.text || item.frameCaption || null,
    audioBed: item.audioBed || null,
    processingState: generationStatus.mediaProcessing || "queued",
    captionsGenerationState: generationStatus.captions || (item.captionTrack ? "ready" : "notRequested"),
    keyMomentsGenerationState: generationStatus.keyMoments || (item.keyMoments?.length ? "ready" : "notRequested"),
    featuredFrameGenerationState: generationStatus.featuredFrame || ((item.isFeaturedFrame || item.featuredFrameTime != null) ? "ready" : "queued"),
    userEditedMetadata: item.userEditedMetadata === true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function syncMediaMetadataForPost(postId, beforeData, afterData) {
  const previousItems = beforeData?.mediaItems || [];
  const nextItems = afterData?.mediaItems || [];
  const authorId = afterData?.authorId || beforeData?.authorId || null;
  const postRef = db.collection("posts").doc(postId);

  const previousMap = new Map(previousItems.map((item) => [item.id, item]));
  const nextMap = new Map(nextItems.map((item) => [item.id, item]));

  const writes = [];

  for (const item of nextItems) {
    const mediaRef = postRef.collection("mediaMeta").doc(item.id);
    writes.push(mediaRef.set(buildMediaMetaDoc(postId, authorId, item), {merge: true}));

    if (item.captionTrack) {
      const track = item.captionTrack;
      writes.push(
        mediaRef.collection("captionTracks").doc(track.id).set({
          captionTrackId: track.id,
          language: track.languageCode || "en",
          source: track.source || (track.editedTranscript ? "userEdited" : "generated"),
          selectedCaptionStyle: track.style || "minimal",
          displayByDefault: track.displayByDefault === true,
          generatedTranscript: track.generatedTranscript || null,
          editedTranscript: track.editedTranscript || null,
          segments: (track.cues || []).map((cue) => ({
            cueId: cue.id,
            startTime: cue.startTime,
            endTime: cue.endTime,
            text: cue.text,
          })),
          lastEditedAt: track.lastEditedAt || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}),
      );
    }

    for (const moment of item.keyMoments || []) {
      writes.push(
        mediaRef.collection("keyMoments").doc(moment.id).set({
          momentId: moment.id,
          time: moment.timestamp,
          label: moment.label,
          kind: moment.kind,
          source: moment.source || "generated",
          sortOrder: moment.sortOrder ?? null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}),
      );
    }
  }

  for (const item of previousItems) {
    if (!nextMap.has(item.id)) {
      writes.push(postRef.collection("mediaMeta").doc(item.id).delete().catch(() => null));
    }
  }

  return Promise.all(writes);
}

exports.onPostMediaMetadataCreate = onDocumentCreated("posts/{postId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const data = snapshot.data();
  if (!Array.isArray(data.mediaItems) || data.mediaItems.length === 0) return;
  await syncMediaMetadataForPost(snapshot.id, null, data);
});

exports.onPostMediaMetadataUpdate = onDocumentUpdated("posts/{postId}", async (event) => {
  const beforeData = event.data?.before?.data();
  const afterData = event.data?.after?.data();
  if (!beforeData && !afterData) return;
  const beforeItems = beforeData?.mediaItems || [];
  const afterItems = afterData?.mediaItems || [];
  if (!beforeItems.length && !afterItems.length) return;
  await syncMediaMetadataForPost(event.params.postId, beforeData, afterData);
});

exports.onPostMediaMetadataDelete = onDocumentDeleted("posts/{postId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const data = snapshot.data();
  const mediaItems = data.mediaItems || [];
  if (!mediaItems.length) return;

  const postRef = db.collection("posts").doc(event.params.postId);
  await Promise.all(
    mediaItems.map((item) => postRef.collection("mediaMeta").doc(item.id).delete().catch(() => null)),
  );
});
