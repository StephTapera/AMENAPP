const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();
const serverTimestamp = admin.firestore.FieldValue.serverTimestamp;

const callableOptions = {
  region: "us-central1",
  enforceAppCheck: true,
  timeoutSeconds: 60,
  memory: "256MiB",
};

const allowedSessionTypes = new Set([
  "morningInspiration",
  "fiveMinuteSelah",
  "prayerSafeTestimonies",
  "churchNotesStudyPath",
  "sermonClipReflection",
  "familySafeWatch",
  "localChurchUpdates",
  "savedVideos",
]);

const allowedQueueTypes = new Set([
  "watchLater",
  "prayerQueue",
  "churchNotes",
  "familyWatch",
  "selahTonight",
  "sermonStudy",
  "testimonyArchive",
]);

const healthyEvents = new Set([
  "media_started",
  "media_completed",
  "media_reflected",
  "media_saved_to_notes",
  "media_saved_to_queue",
  "media_prayer_action",
  "media_take_break",
  "media_session_started",
  "media_session_completed",
  "captions_enabled",
  "captions_disabled",
  "transcript_opened",
  "transcript_segment_tapped",
  "key_moment_tapped",
  "playback_speed_changed",
  "audio_mode_enabled",
  "low_bandwidth_enabled",
  "offline_save_started",
  "offline_save_completed",
  "doom_scroll_interruption_shown",
  "safety_mode_enabled",
  "safety_gate_shown",
  "report_submitted",
  "not_interested_submitted",
  "media_search_performed",
  "timestamped_comment_created",
  "ai_metadata_draft_generated",
  "ai_metadata_approved",
  "ai_metadata_rejected",
]);

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return request.auth.uid;
}

function data(request) {
  return request.data && typeof request.data === "object" ? request.data : {};
}

function requiredString(input, field, maxLength = 200) {
  const value = input[field];
  if (typeof value !== "string" || value.trim().length === 0 || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function optionalString(input, field, maxLength = 1000) {
  const value = input[field];
  if (value === undefined || value === null || value === "") return "";
  if (typeof value !== "string" || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value.trim();
}

function boundedNumber(input, field, min, max, fallback) {
  const raw = input[field];
  if (raw === undefined || raw === null || raw === "") return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < min || value > max) {
    throw new HttpsError("invalid-argument", `${field} is out of range.`);
  }
  return value;
}

async function audit(uid, action, payload = {}) {
  await db.collection("mediaAuditLogs").add({
    uid,
    action,
    payload,
    createdAt: serverTimestamp(),
  });
}

async function rateLimit(uid, action, maxCount = 30, windowMs = 60 * 1000) {
  const bucket = Math.floor(Date.now() / windowMs);
  const ref = db.collection("mediaRateLimits").doc(`${uid}_${action}_${bucket}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists ? snap.data().count || 0 : 0;
    if (count >= maxCount) {
      throw new HttpsError("resource-exhausted", "Please slow down and try again shortly.");
    }
    tx.set(ref, {
      uid,
      action,
      bucket,
      count: count + 1,
      updatedAt: serverTimestamp(),
    }, {merge: true});
  });
}

async function getViewablePost(postId) {
  const postSnap = await db.collection("posts").doc(postId).get();
  if (!postSnap.exists) {
    throw new HttpsError("not-found", "Media post was not found.");
  }
  const post = postSnap.data() || {};
  if (post.removed === true || post.hidden === true || post.status === "removed" || post.status === "hidden") {
    throw new HttpsError("permission-denied", "Media is not available.");
  }
  return {ref: postSnap.ref, data: post};
}

async function getMedia(postId, mediaId) {
  const {ref: postRef, data: post} = await getViewablePost(postId);
  const mediaSnap = await postRef.collection("mediaMeta").doc(mediaId).get();
  if (!mediaSnap.exists) {
    const item = (post.mediaItems || []).find((entry) => entry.id === mediaId);
    if (!item) {
      throw new HttpsError("not-found", "Media item was not found.");
    }
    return {postRef, post, mediaRef: postRef.collection("mediaMeta").doc(mediaId), media: item};
  }
  const media = mediaSnap.data() || {};
  if (media.status === "removed" || media.status === "hidden" || media.safety?.status === "removed") {
    throw new HttpsError("permission-denied", "Media is not available.");
  }
  return {postRef, post, mediaRef: mediaSnap.ref, media};
}

function canApproveMetadata(uid, post) {
  return post.authorId === uid || post.ownerUid === uid;
}

exports.updateMediaProgress = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "updateMediaProgress", 120);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const durationSeconds = boundedNumber(input, "durationSeconds", 1, 24 * 60 * 60, 1);
  const progressSeconds = Math.min(boundedNumber(input, "progressSeconds", 0, durationSeconds, 0), durationSeconds);
  const percentComplete = Math.min(Math.max((progressSeconds / durationSeconds) * 100, 0), 100);
  const completed = percentComplete >= 95 || input.completed === true;
  await getMedia(postId, mediaId);

  await db.collection("users").doc(uid).collection("mediaProgress").doc(mediaId).set({
    mediaId,
    postId,
    progressSeconds,
    durationSeconds,
    percentComplete,
    completed,
    sourceSurface: optionalString(input, "sourceSurface", 60),
    lastWatchedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true});

  await audit(uid, "updateMediaProgress", {postId, mediaId, completed});
  return {ok: true, percentComplete, completed};
});

exports.createMediaSession = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "createMediaSession", 20);
  const input = data(request);
  const sessionType = requiredString(input, "sessionType", 80);
  if (!allowedSessionTypes.has(sessionType)) {
    throw new HttpsError("invalid-argument", "Unsupported session type.");
  }
  const maxItems = Math.min(Math.max(Math.round(boundedNumber(input, "maxItems", 1, 12, 3)), 3), 12);
  const maxDurationSeconds = Math.min(Math.max(Math.round(boundedNumber(input, "maxDurationSeconds", 60, 3600, 480)), 60), 3600);
  const sourceSurface = optionalString(input, "sourceSurface", 60);
  const safetyMode = optionalString(input, "safetyMode", 80);

  const querySnap = await db.collection("posts")
      .where("removed", "!=", true)
      .limit(maxItems)
      .get()
      .catch(() => null);
  const itemIds = [];
  if (querySnap) {
    querySnap.docs.forEach((doc) => {
      const post = doc.data() || {};
      const mediaItems = Array.isArray(post.mediaItems) ? post.mediaItems : [];
      mediaItems.slice(0, 1).forEach((item) => {
        if (item?.id && itemIds.length < maxItems) itemIds.push(`${doc.id}:${item.id}`);
      });
    });
  }

  const sessionRef = db.collection("users").doc(uid).collection("mediaSessions").doc();
  await sessionRef.set({
    sessionType,
    itemIds,
    currentIndex: 0,
    completed: false,
    startedAt: serverTimestamp(),
    endedAt: null,
    reflectionPromptShown: false,
    sourceSurface,
    safetyMode,
    maxItems,
    maxDurationSeconds,
    finiteQueue: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  await audit(uid, "createMediaSession", {sessionId: sessionRef.id, sessionType, itemCount: itemIds.length});
  return {sessionId: sessionRef.id, items: itemIds, maxItems, maxDurationSeconds};
});

exports.completeMediaSession = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "completeMediaSession", 60);
  const input = data(request);
  const sessionId = requiredString(input, "sessionId");
  const finalAction = requiredString(input, "finalAction", 80);
  const ref = db.collection("users").doc(uid).collection("mediaSessions").doc(sessionId);
  await ref.set({
    completed: true,
    endedAt: serverTimestamp(),
    finalAction,
    updatedAt: serverTimestamp(),
  }, {merge: true});
  await audit(uid, "completeMediaSession", {sessionId, finalAction});
  return {ok: true};
});

exports.saveToMediaQueue = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "saveToMediaQueue", 40);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const queueType = requiredString(input, "queueType", 80);
  if (!allowedQueueTypes.has(queueType)) {
    throw new HttpsError("invalid-argument", "Unsupported media queue.");
  }
  await getMedia(postId, mediaId);
  const itemRef = db.collection("users").doc(uid)
      .collection("mediaQueues").doc(queueType)
      .collection("items").doc(mediaId);
  await itemRef.set({
    postId,
    mediaId,
    queueType,
    addedAt: serverTimestamp(),
    sourceSurface: optionalString(input, "sourceSurface", 60),
    note: optionalString(input, "note", 1000),
  }, {merge: true});
  await audit(uid, "saveToMediaQueue", {postId, mediaId, queueType});
  return {ok: true, itemId: itemRef.id};
});

exports.reportMedia = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "reportMedia", 10, 5 * 60 * 1000);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const reason = requiredString(input, "reason", 120);
  const details = optionalString(input, "details", 2000);
  const {post, media} = await getMedia(postId, mediaId);
  const reportRef = db.collection("mediaModerationQueue").doc();
  await reportRef.set({
    mediaId,
    postId,
    reporterUid: uid,
    ownerUid: post.authorId || media.ownerUid || null,
    reason,
    details,
    status: "pending",
    createdAt: serverTimestamp(),
    reviewedAt: null,
  });
  await audit(uid, "reportMedia", {postId, mediaId, reason});
  return {reportId: reportRef.id};
});

exports.notInterestedMedia = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "notInterestedMedia", 60);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  await getMedia(postId, mediaId);
  await db.collection("users").doc(uid).collection("mediaNotInterested").doc(mediaId).set({
    postId,
    mediaId,
    reason: optionalString(input, "reason", 500),
    createdAt: serverTimestamp(),
  }, {merge: true});
  await audit(uid, "notInterestedMedia", {postId, mediaId});
  return {ok: true};
});

exports.createMediaCompletionEvent = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "createMediaCompletionEvent", 80);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const action = requiredString(input, "action", 80);
  await getMedia(postId, mediaId);
  const ref = await db.collection("mediaCompletionEvents").add({
    uid,
    postId,
    mediaId,
    sessionId: optionalString(input, "sessionId", 200),
    action,
    createdAt: serverTimestamp(),
  });
  await audit(uid, "createMediaCompletionEvent", {postId, mediaId, action});
  return {eventId: ref.id};
});

exports.recordMediaEvent = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "recordMediaEvent", 180);
  const input = data(request);
  const eventName = requiredString(input, "eventName", 120);
  if (!healthyEvents.has(eventName)) {
    throw new HttpsError("invalid-argument", "Unsupported media event.");
  }
  const ref = await db.collection("mediaAnalyticsEvents").add({
    uid,
    eventName,
    postId: optionalString(input, "postId", 200),
    mediaId: optionalString(input, "mediaId", 200),
    sessionId: optionalString(input, "sessionId", 200),
    metadata: typeof input.metadata === "object" && input.metadata ? input.metadata : {},
    createdAt: serverTimestamp(),
  });
  return {eventId: ref.id};
});

exports.saveMediaAccessibilityPreferences = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "saveMediaAccessibilityPreferences", 30);
  const input = data(request);
  const allowed = [
    "captionsDefaultOn",
    "captionSize",
    "highContrastCaptions",
    "reduceMotion",
    "reduceTransparency",
    "autoplayDisabled",
    "sensorySafeMode",
    "audioDescriptionEnabled",
    "simplifiedTranscript",
    "preferredLanguage",
    "slowerTransitions",
    "hapticReduction",
    "flashReduction",
    "voiceControlLabels",
    "persistentControls",
    "largerTapTargets",
  ];
  const prefs = {};
  allowed.forEach((field) => {
    if (Object.prototype.hasOwnProperty.call(input, field)) prefs[field] = input[field];
  });
  prefs.updatedAt = serverTimestamp();
  await db.collection("users").doc(uid).collection("accessibility").doc("mediaPreferences")
      .collection("main").doc("main").set(prefs, {merge: true});
  await audit(uid, "saveMediaAccessibilityPreferences");
  return {ok: true};
});

exports.searchMedia = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "searchMedia", 60);
  const input = data(request);
  const query = requiredString(input, "query", 200).toLowerCase();
  const limit = Math.min(Math.max(Math.round(boundedNumber(input, "limit", 1, 50, 20)), 1), 50);
  const snap = await db.collection("mediaSearchIndex")
      .where("discoverable", "==", true)
      .limit(limit)
      .get();
  const items = snap.docs
      .map((doc) => ({id: doc.id, ...doc.data()}))
      .filter((item) => {
        const haystack = [
          item.title,
          item.captionText,
          item.transcriptText,
          ...(item.scriptureRefs || []),
          ...(item.topics || []),
        ].join(" ").toLowerCase();
        return haystack.includes(query) && item.hidden !== true && item.removed !== true && item.safetyRating !== "unsafe";
      })
      .slice(0, limit);
  await audit(uid, "searchMedia", {query, count: items.length});
  return {items};
});

exports.rankMedia = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "rankMedia", 60);
  const input = data(request);
  const limit = Math.min(Math.max(Math.round(boundedNumber(input, "limit", 1, 50, 20)), 1), 50);
  const snap = await db.collection("mediaRankingSignals").limit(100).get();
  const ranked = snap.docs.map((doc) => {
    const d = doc.data() || {};
    const score =
      Number(d.spiritualUsefulnessScore || 0) +
      Number(d.safetyScore || 0) +
      Number(d.originalityScore || 0) +
      Number(d.reflectionScore || 0) +
      Number(d.saveScore || 0) +
      Number(d.prayerScore || 0) +
      Number(d.trustedCreatorScore || 0) +
      Number(d.churchRelevanceScore || 0) +
      Number(d.familySafeBoost || 0) +
      Number(d.completionQualityScore || 0) -
      Number(d.doomScrollRiskScore || 0) -
      Number(d.sensationalismScore || 0) -
      Number(d.repeatFatigueScore || 0) -
      Number(d.reportPenalty || 0);
    return {mediaId: doc.id, postId: d.postId || "", score};
  }).sort((a, b) => b.score - a.score).slice(0, limit);
  await audit(uid, "rankMedia", {surface: optionalString(input, "surface", 80), count: ranked.length});
  return {items: ranked.map(({score, ...publicItem}) => publicItem)};
});

exports.createMediaUploadSession = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "createMediaUploadSession", 20);
  const input = data(request);
  const mediaType = requiredString(input, "mediaType", 40);
  const fileName = requiredString(input, "fileName", 200);
  const contentType = requiredString(input, "contentType", 100);
  const fileSizeBytes = boundedNumber(input, "fileSizeBytes", 1, 500 * 1024 * 1024, 1);
  const uploadSessionRef = db.collection("mediaUploadSessions").doc();
  const mediaId = uploadSessionRef.id;
  const storagePath = `mediaUploads/${uid}/${mediaId}/raw/${fileName}`;
  await uploadSessionRef.set({
    uid,
    mediaId,
    mediaType,
    fileName,
    contentType,
    fileSizeBytes,
    storagePath,
    status: "created",
    createdAt: serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 60 * 1000),
  });
  await audit(uid, "createMediaUploadSession", {mediaType, mediaId});
  return {uploadSessionId: uploadSessionRef.id, storagePath, uploadUrlOrPath: storagePath, expiresAt: Date.now() + 30 * 60 * 1000};
});

exports.finalizeMediaUpload = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "finalizeMediaUpload", 20);
  const input = data(request);
  const uploadSessionId = requiredString(input, "uploadSessionId");
  const storagePath = requiredString(input, "storagePath", 1000);
  const uploadRef = db.collection("mediaUploadSessions").doc(uploadSessionId);
  const uploadSnap = await uploadRef.get();
  if (!uploadSnap.exists || uploadSnap.data().uid !== uid || uploadSnap.data().storagePath !== storagePath) {
    throw new HttpsError("permission-denied", "Upload session is not valid.");
  }
  const postId = optionalString(input, "postId", 200) || db.collection("posts").doc().id;
  const mediaId = uploadSnap.data().mediaId || uploadSessionId;
  await db.collection("posts").doc(postId).collection("mediaMeta").doc(mediaId).set({
    postId,
    mediaId,
    authorId: uid,
    storagePath,
    status: "pending",
    safety: {status: "pending"},
    aiMetadataState: {
      captionsStatus: "none",
      keyMomentsStatus: "none",
      summaryStatus: "none",
      explanationStatus: "none",
    },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true});
  await uploadRef.set({status: "finalized", postId, mediaId, finalizedAt: serverTimestamp()}, {merge: true});
  await audit(uid, "finalizeMediaUpload", {postId, mediaId});
  return {postId, mediaId, status: "pending"};
});

exports.generateMediaDraftMetadata = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "generateMediaDraftMetadata", 10);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const {postRef, post} = await getMedia(postId, mediaId);
  if (!canApproveMetadata(uid, post)) throw new HttpsError("permission-denied", "Only the creator can request drafts.");
  const draftRef = postRef.collection("mediaMeta").doc(mediaId).collection("draftMetadata").doc();
  await draftRef.set({
    requestedOutputs: Array.isArray(input.requestedOutputs) ? input.requestedOutputs : [],
    status: "draft",
    generatedBy: "system",
    approvedByUser: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  await audit(uid, "generateMediaDraftMetadata", {postId, mediaId, draftId: draftRef.id});
  return {draftIds: [draftRef.id], status: "draft"};
});

exports.approveMediaMetadata = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "approveMediaMetadata", 30);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const draftType = requiredString(input, "draftType", 80);
  const draftId = requiredString(input, "draftId");
  const {postRef, post} = await getMedia(postId, mediaId);
  if (!canApproveMetadata(uid, post)) throw new HttpsError("permission-denied", "Only the creator can approve metadata.");
  const collectionName = draftType === "keyMoments" ? "keyMoments" : draftType === "captions" ? "captionTracks" : "draftMetadata";
  await postRef.collection("mediaMeta").doc(mediaId).collection(collectionName).doc(draftId).set({
    status: "approved",
    approvedByUser: true,
    approvedBy: uid,
    approvedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true});
  await audit(uid, "approveMediaMetadata", {postId, mediaId, draftType, draftId});
  return {approved: true, publicPath: `posts/${postId}/mediaMeta/${mediaId}/${collectionName}/${draftId}`};
});

exports.rejectMediaMetadata = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "rejectMediaMetadata", 30);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const draftType = requiredString(input, "draftType", 80);
  const draftId = requiredString(input, "draftId");
  const {postRef, post} = await getMedia(postId, mediaId);
  if (!canApproveMetadata(uid, post)) throw new HttpsError("permission-denied", "Only the creator can reject metadata.");
  await postRef.collection("mediaMeta").doc(mediaId).collection("draftMetadata").doc(draftId).set({
    draftType,
    status: "rejected",
    approvedByUser: false,
    rejectedBy: uid,
    reason: optionalString(input, "reason", 1000),
    rejectedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true});
  await audit(uid, "rejectMediaMetadata", {postId, mediaId, draftType, draftId});
  return {rejected: true};
});

exports.publishMediaPost = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const postId = requiredString(data(request), "postId");
  const postSnap = await db.collection("posts").doc(postId).get();
  if (!postSnap.exists || !canApproveMetadata(uid, postSnap.data() || {})) {
    throw new HttpsError("permission-denied", "Only the creator can publish media.");
  }
  await postSnap.ref.set({status: "published", publishedAt: serverTimestamp(), updatedAt: serverTimestamp()}, {merge: true});
  await audit(uid, "publishMediaPost", {postId});
  return {postId, status: "published"};
});

exports.moderateMediaPost = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const isModerator = request.auth.token.admin === true || request.auth.token.moderator === true;
  if (!isModerator) throw new HttpsError("permission-denied", "Moderator access is required.");
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const status = requiredString(input, "status", 80);
  const {postRef} = await getMedia(postId, mediaId);
  await postRef.collection("mediaMeta").doc(mediaId).set({
    "safety.status": status,
    moderationVersion: admin.firestore.FieldValue.increment(1),
    reviewedAt: serverTimestamp(),
    reviewedBy: uid,
  }, {merge: true});
  await audit(uid, "moderateMediaPost", {postId, mediaId, status});
  return {ok: true};
});

exports.generateCaptionDraft = exports.generateMediaDraftMetadata;
exports.generateKeyMomentsDraft = exports.generateMediaDraftMetadata;

exports.translateCaptions = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "translateCaptions", 20);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  await getMedia(postId, mediaId);
  const targetLanguage = requiredString(input, "targetLanguage", 20);
  await audit(uid, "translateCaptions", {postId, mediaId, targetLanguage});
  return {status: "draft", approvedByUser: false};
});

exports.explainMediaMoment = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "explainMediaMoment", 20);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  await getMedia(postId, mediaId);
  await audit(uid, "explainMediaMoment", {postId, mediaId});
  return {status: "unavailable", explanation: null};
});

exports.createTimestampedComment = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await rateLimit(uid, "createTimestampedComment", 20);
  const input = data(request);
  const postId = requiredString(input, "postId");
  const mediaId = requiredString(input, "mediaId");
  const body = requiredString(input, "body", 2000);
  const timestampSeconds = boundedNumber(input, "timestampSeconds", 0, 24 * 60 * 60, 0);
  const {postRef} = await getMedia(postId, mediaId);
  const commentRef = postRef.collection("comments").doc();
  await commentRef.set({
    body,
    text: body,
    authorUid: uid,
    authorId: uid,
    mediaId,
    timestampSeconds,
    imageIndex: input.imageIndex ?? null,
    keyMomentId: optionalString(input, "keyMomentId", 200),
    scriptureRefs: Array.isArray(input.scriptureRefs) ? input.scriptureRefs.slice(0, 12) : [],
    safetyStatus: "pending",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  await audit(uid, "createTimestampedComment", {postId, mediaId, commentId: commentRef.id});
  return {commentId: commentRef.id, safetyStatus: "pending"};
});
