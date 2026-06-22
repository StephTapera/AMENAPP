const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = admin.firestore();

const ALLOWED_FEEDBACK_ACTIONS = new Set([
  "impression",
  "tap",
  "dismiss",
  "show_less",
  "mute_topic",
  "mute_type",
  "hide_all",
  "report_issue",
]);

const CONTEXT_EXPIRATION_HOURS = {
  inConversation: 24,
  scriptureFocus: 72,
  sharedInYourCircles: 48,
  resonatingNearby: 24,
  bereanInsight: 24 * 7,
  churchPulse: 48,
  gentleFollowUp: 24 * 14,
  livePrayerMoment: 2,
  communityQuestion: 48,
  relevantNow: 24,
};

const DEFAULT_MINIMUMS = {
  normal: 0.72,
  sensitive: 0.86,
  livePrayer: 0.80,
  bereanInsight: 0.78,
};

function requireAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return uid;
}

function preferenceDoc(uid) {
  return db.collection("users").doc(uid)
      .collection("feedPreferences").doc("contextLabels");
}

function clamp(value, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value));
}

function normalizeTopicKey(raw) {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  return trimmed.toLowerCase().replace(/\s+/g, "_");
}

function normalizeTitle(raw) {
  return String(raw || "").replace(/\s+/g, " ").trim();
}

function coerceStringArray(value) {
  return Array.isArray(value) ? value.filter((entry) => typeof entry === "string") : [];
}

function normalizePosts(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    if (typeof item.id !== "string" ||
        typeof item.authorId !== "string" ||
        typeof item.content !== "string" ||
        typeof item.category !== "string" ||
        typeof item.createdAt !== "number") {
      return [];
    }
    return [{
      id: item.id,
      authorId: item.authorId,
      content: item.content,
      category: item.category,
      topicTag: typeof item.topicTag === "string" ? item.topicTag : null,
      amenCount: typeof item.amenCount === "number" ? item.amenCount : 0,
      commentCount: typeof item.commentCount === "number" ? item.commentCount : 0,
      createdAt: item.createdAt,
      verseRef: typeof item.verseRef === "string" ? item.verseRef : null,
      churchId: typeof item.churchId === "string" ? item.churchId : null,
      communityId: typeof item.communityId === "string" ? item.communityId : null,
      linkedPrayerRequestId: typeof item.linkedPrayerRequestId === "string" ?
        item.linkedPrayerRequestId : null,
      lowTrustAuthor: item.lowTrustAuthor === true,
      flaggedForReview: item.flaggedForReview === true,
      removed: item.removed === true,
    }];
  });
}

function scoreMomentum(post, ageHours) {
  const engagement = Math.min(post.amenCount * 0.02 + post.commentCount * 0.04, 1);
  const freshness = clamp(1 - ageHours / 72);
  return clamp(engagement * 0.6 + freshness * 0.4);
}

function scoreCommunity(post, request, userContext) {
  let score = 0;
  if (request.followingIds.includes(post.authorId)) score += 0.45;
  if (post.churchId && userContext.churchId && post.churchId === userContext.churchId) score += 0.3;
  if (post.communityId && userContext.communityId && post.communityId === userContext.communityId) score += 0.2;
  return clamp(score);
}

function scoreScripture(post, userContext) {
  const verseRef = (post.verseRef || "").trim();
  const scriptureTopics = (userContext.scriptureTopics || [])
      .map((value) => String(value).toLowerCase());
  const content = post.content.toLowerCase();
  let score = verseRef ? 0.65 : 0;
  if (scriptureTopics.some((topic) => topic && content.includes(topic))) score += 0.2;
  if (/\bromans\b|\bpsalm\b|\bjohn\b|\bhebrews\b|\bcorinthians\b/.test(content)) score += 0.15;
  return clamp(score);
}

function scorePersonalRelevance(post, request, userContext) {
  const topicKey = normalizeTopicKey(post.topicTag);
  const content = post.content.toLowerCase();
  let score = 0;
  if (topicKey && request.interests.engagedTopics[topicKey]) {
    score += clamp(request.interests.engagedTopics[topicKey] / 2) * 0.45;
  }
  if (request.interests.engagedAuthors[post.authorId]) {
    score += clamp(request.interests.engagedAuthors[post.authorId] / 6) * 0.2;
  }
  if (request.interests.preferredCategories[post.category]) {
    score += clamp(request.interests.preferredCategories[post.category]) * 0.15;
  }
  const allInterestTerms = [
    ...(userContext.interests || []),
    ...(userContext.prayerInterests || []),
    ...(request.interests.onboardingGoals || []),
  ].map((value) => String(value).toLowerCase());
  if (allInterestTerms.some((term) => term && content.includes(term))) {
    score += 0.2;
  }
  return clamp(score);
}

function scoreTrust(post) {
  if (post.lowTrustAuthor || post.flaggedForReview || post.removed) {
    return 0;
  }
  const baitPattern = /\bviral\b|\btrending\b|\bbreaking\b|\bexploding\b|\bhot topic\b/i.test(post.content);
  return baitPattern ? 0.25 : 1;
}

function classifySensitive(content) {
  return /\bpolitics\b|\babuse\b|\bsuicide\b|\bwar\b|\bviolence\b|\bchurch hurt\b/i.test(content);
}

function chooseContextType(post, scores) {
  if (post.lowTrustAuthor || post.flaggedForReview || post.removed) return null;
  if (post.linkedPrayerRequestId && scores.momentumScore >= 0.8) return "livePrayerMoment";
  if ((post.verseRef || post.category === "scripture") && scores.scriptureScore >= 0.72) {
    return "scriptureFocus";
  }
  if (post.churchId && scores.communityScore >= 0.72) return "churchPulse";
  if (scores.communityScore >= 0.74 && post.communityId) return "sharedInYourCircles";
  if (scores.personalRelevanceScore >= 0.78 && scores.scriptureScore >= 0.55) {
    return "bereanInsight";
  }
  if (scores.momentumScore >= 0.76 && post.commentCount >= 3) return "communityQuestion";
  if (scores.communityScore >= 0.68) return "resonatingNearby";
  if (scores.personalRelevanceScore >= 0.7) return "gentleFollowUp";
  if (scores.momentumScore >= 0.72) return "inConversation";
  if (scores.personalRelevanceScore >= 0.64) return "relevantNow";
  return null;
}

function destinationForType(type) {
  switch (type) {
    case "scriptureFocus":
      return "scriptureCluster";
    case "churchPulse":
      return "churchPulse";
    case "livePrayerMoment":
      return "prayerMoment";
    case "bereanInsight":
      return "bereanInsight";
    case "communityQuestion":
      return "postThread";
    case "gentleFollowUp":
    case "relevantNow":
      return "whyThisAppeared";
    default:
      return "topicFeed";
  }
}

function confidenceThresholdForType(type, sensitive) {
  if (sensitive) return DEFAULT_MINIMUMS.sensitive;
  if (type === "livePrayerMoment") return DEFAULT_MINIMUMS.livePrayer;
  if (type === "bereanInsight") return DEFAULT_MINIMUMS.bereanInsight;
  return DEFAULT_MINIMUMS.normal;
}

function reasonForType(type, post) {
  switch (type) {
    case "scriptureFocus":
      return "You’re seeing this because it connects with scripture themes people have been reflecting on recently.";
    case "sharedInYourCircles":
      return "You’re seeing this because people in your circles are sharing and responding to this topic thoughtfully.";
    case "churchPulse":
      return "You’re seeing this because people in your church community are praying and reflecting around this topic.";
    case "bereanInsight":
      return "You’re seeing this because it connects with scripture themes and study topics you’ve shown interest in.";
    case "livePrayerMoment":
      return "You’re seeing this because there is an active prayer response around this right now.";
    case "communityQuestion":
      return "You’re seeing this because people are responding thoughtfully and the discussion is growing with care.";
    case "gentleFollowUp":
      return "You’re seeing this because it connects with topics you’ve chosen to revisit or save.";
    case "resonatingNearby":
      return "You’re seeing this because it is resonating in nearby faith communities.";
    case "relevantNow":
      return "You’re seeing this because it connects with topics you’ve shown interest in recently.";
    default:
      return `You’re seeing this because ${normalizeTitle(post.topicTag || "this topic")} is drawing thoughtful conversation right now.`;
  }
}

function buildContextTitle(post, type) {
  if (type === "scriptureFocus" && post.verseRef) return normalizeTitle(post.verseRef);
  return normalizeTitle(post.topicTag || post.category || "Reflection");
}

function buildExpiration(type) {
  const hours = CONTEXT_EXPIRATION_HOURS[type] || 24;
  return new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
}

function computeContextScore(post, request, userContext) {
  const ageHours = Math.max(0, (Date.now() / 1000 - post.createdAt) / 3600);
  const momentumScore = scoreMomentum(post, ageHours);
  const communityScore = scoreCommunity(post, request, userContext);
  const scriptureScore = scoreScripture(post, userContext);
  const personalRelevanceScore = scorePersonalRelevance(post, request, userContext);
  const trustScore = scoreTrust(post);
  const contextScore = (
    momentumScore * 0.2 +
    communityScore * 0.2 +
    scriptureScore * 0.2 +
    personalRelevanceScore * 0.2 +
    trustScore * 0.2
  );

  return {
    ageHours,
    momentumScore,
    communityScore,
    scriptureScore,
    personalRelevanceScore,
    trustScore,
    contextScore: clamp(contextScore),
  };
}

function buildContextPayload(post, request, userContext) {
  const scores = computeContextScore(post, request, userContext);
  const contextType = chooseContextType(post, scores);
  if (!contextType) return null;

  const title = buildContextTitle(post, contextType);
  if (!title || title.length < 3) return null;

  const sensitive = classifySensitive(`${post.content} ${title}`);
  const threshold = confidenceThresholdForType(contextType, sensitive);
  if (scores.contextScore < threshold) return null;
  if (sensitive &&
      !["scriptureFocus", "churchPulse", "livePrayerMoment", "gentleFollowUp", "inConversation"].includes(contextType)) {
    return null;
  }

  return {
    contextId: `${post.id}:${contextType}`,
    contextType,
    contextTitle: title,
    contextReason: reasonForType(contextType, post),
    contextConfidence: Number(scores.contextScore.toFixed(3)),
    contextPriority: Math.round(scores.contextScore * 100),
    contextDestinationType: destinationForType(contextType),
    contextDestinationId: post.linkedPrayerRequestId || post.topicTag || post.communityId || post.churchId || null,
    contextTopicId: normalizeTopicKey(post.topicTag),
    contextVerseRef: post.verseRef || null,
    contextChurchId: post.churchId || null,
    contextCommunityId: post.communityId || null,
    contextExpiresAt: buildExpiration(contextType),
    contextIsSensitive: sensitive,
    contextIsDismissible: true,
    contextAnalyticsId: `ctx_${post.id}_${contextType}`,
  };
}

function validateFeedbackAction(action) {
  return ALLOWED_FEEDBACK_ACTIONS.has(action);
}

function normalizeRankRequest(data, uid) {
  const interests = data && typeof data.interests === "object" && data.interests ? data.interests : {};
  return {
    userId: uid,
    posts: normalizePosts(data && data.posts),
    interests: {
      engagedTopics: interests.engagedTopics && typeof interests.engagedTopics === "object" ?
        interests.engagedTopics : {},
      engagedAuthors: interests.engagedAuthors && typeof interests.engagedAuthors === "object" ?
        interests.engagedAuthors : {},
      preferredCategories: interests.preferredCategories && typeof interests.preferredCategories === "object" ?
        interests.preferredCategories : {},
      onboardingGoals: coerceStringArray(interests.onboardingGoals),
    },
    followingIds: coerceStringArray(data && data.followingIds),
    sessionCardsServed: typeof (data && data.sessionCardsServed) === "number" ? data.sessionCardsServed : 0,
    sessionCap: typeof (data && data.sessionCap) === "number" ? data.sessionCap : 25,
  };
}

async function loadUserContext(uid) {
  const [userDoc, feedPrefsDoc] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("userFeedPrefs").doc(uid).get(),
  ]);
  const user = userDoc.data() || {};
  const prefs = feedPrefsDoc.data() || {};
  return {
    churchId: typeof user.churchId === "string" ? user.churchId : undefined,
    city: typeof user.city === "string" ? user.city : undefined,
    communityId: typeof user.communityId === "string" ? user.communityId : undefined,
    interests: coerceStringArray(user.interests),
    scriptureTopics: coerceStringArray(user.scriptureTopics),
    prayerInterests: coerceStringArray(prefs.prayerInterests),
  };
}

function buildRankedFeedResponse(request, userContext) {
  const contextsByPostId = {};
  const ranked = request.posts.map((post) => {
    const scores = computeContextScore(post, request, userContext);
    const context = buildContextPayload(post, request, userContext);
    if (context) {
      contextsByPostId[post.id] = context;
    }
    const engagementScore = clamp(post.amenCount * 0.015 + post.commentCount * 0.03);
    const recencyScore = clamp(1 - ((Date.now() / 1000 - post.createdAt) / (72 * 3600)));
    const finalScore = scores.contextScore * 0.55 + engagementScore * 0.2 + recencyScore * 0.25;
    return {postId: post.id, finalScore};
  }).sort((left, right) => right.finalScore - left.finalScore);

  const rankedIds = ranked.map((entry) => entry.postId);
  const sessionCapRemaining = Math.max(
      0,
      request.sessionCap - request.sessionCardsServed - Object.keys(contextsByPostId).length,
  );

  return {
    rankedIds,
    sessionCapRemaining,
    sessionExhausted: sessionCapRemaining === 0,
    contextsByPostId,
  };
}

const computeFeedContextLabels = onCall(async (request) => {
  const uid = requireAuth(request);
  const normalizedRequest = normalizeRankRequest(request.data || {}, uid);
  const userContext = await loadUserContext(uid);

  return {
    contextsByPostId: Object.fromEntries(
        normalizedRequest.posts
            .map((post) => [post.id, buildContextPayload(post, normalizedRequest, userContext)])
            .filter((entry) => entry[1] !== null),
    ),
    minimums: DEFAULT_MINIMUMS,
  };
});

const attachFeedContextToRankedPosts = onCall(async (request) => {
  const uid = requireAuth(request);
  const normalizedRequest = normalizeRankRequest(request.data || {}, uid);
  if (normalizedRequest.posts.length === 0) {
    return {
      rankedIds: [],
      sessionCapRemaining: normalizedRequest.sessionCap,
      sessionExhausted: false,
      contextsByPostId: {},
    };
  }

  const userContext = await loadUserContext(uid);
  return buildRankedFeedResponse(normalizedRequest, userContext);
});

const updateUserContextLabelPreferences = onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  await preferenceDoc(uid).set({
    disabled: data.disabled === true,
    mutedTopicIds: coerceStringArray(data.mutedTopicIds),
    mutedTypes: coerceStringArray(data.mutedTypes),
    hiddenContextIds: coerceStringArray(data.hiddenContextIds),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {success: true};
});

const trackContextLabelEvent = onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  const action = typeof data.action === "string" ? data.action : "";
  if (!validateFeedbackAction(action)) {
    throw new HttpsError("invalid-argument", "Unsupported context feedback action.");
  }
  if (typeof data.contextId !== "string" || typeof data.postId !== "string") {
    throw new HttpsError("invalid-argument", "contextId and postId are required.");
  }
  if (typeof data.userId === "string" && data.userId !== uid) {
    throw new HttpsError("permission-denied", "Cannot write feedback for another user.");
  }

  await db.collection("users").doc(uid)
      .collection("feedPreferences").doc("contextLabelEvents")
      .collection("events").add({
        uid,
        action,
        contextId: data.contextId,
        topicId: typeof data.topicId === "string" ? data.topicId : null,
        contextType: typeof data.contextType === "string" ? data.contextType : null,
        postId: data.postId,
        confidence: typeof data.confidence === "number" ? data.confidence : null,
        destinationType: typeof data.destinationType === "string" ? data.destinationType : null,
        feedSessionId: typeof data.feedSessionId === "string" ? data.feedSessionId : null,
        rankPosition: typeof data.rankPosition === "number" ? data.rankPosition : null,
        isSensitive: data.isSensitive === true,
        reasonCode: typeof data.reasonCode === "string" ? data.reasonCode : null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

  return {success: true};
});

const suppressContextLabelForUser = onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  const action = typeof data.action === "string" ? data.action : "";
  if (!validateFeedbackAction(action)) {
    throw new HttpsError("invalid-argument", "Unsupported context feedback action.");
  }

  const updates = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (action === "hide_all") {
    updates.disabled = true;
  } else if (action === "mute_topic") {
    if (typeof data.topicId !== "string" || !data.topicId.trim()) {
      throw new HttpsError("invalid-argument", "topicId is required for mute_topic.");
    }
    updates.mutedTopicIds = admin.firestore.FieldValue.arrayUnion(data.topicId.trim());
  } else if (action === "mute_type") {
    if (typeof data.contextType !== "string" || !data.contextType.trim()) {
      throw new HttpsError("invalid-argument", "contextType is required for mute_type.");
    }
    updates.mutedTypes = admin.firestore.FieldValue.arrayUnion(data.contextType.trim());
  } else {
    if (typeof data.contextId !== "string" || !data.contextId.trim()) {
      throw new HttpsError("invalid-argument", "contextId is required for this action.");
    }
    updates.hiddenContextIds = admin.firestore.FieldValue.arrayUnion(data.contextId.trim());
  }

  await preferenceDoc(uid).set(updates, {merge: true});
  return {success: true};
});

module.exports = {
  DEFAULT_MINIMUMS,
  buildContextPayload,
  buildRankedFeedResponse,
  computeContextScore,
  computeFeedContextLabels,
  attachFeedContextToRankedPosts,
  suppressContextLabelForUser,
  trackContextLabelEvent,
  updateUserContextLabelPreferences,
  validateFeedbackAction,
};
