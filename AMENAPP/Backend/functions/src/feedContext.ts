import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

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

const CONTEXT_EXPIRATION_HOURS: Record<string, number> = {
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

type FeedPostPayload = {
    id: string;
    authorId: string;
    content: string;
    category: string;
    topicTag?: string | null;
    amenCount: number;
    commentCount: number;
    createdAt: number;
    verseRef?: string | null;
    churchId?: string | null;
    communityId?: string | null;
    linkedPrayerRequestId?: string | null;
    lowTrustAuthor?: boolean;
    flaggedForReview?: boolean;
    removed?: boolean;
};

type FeedInterestsPayload = {
    engagedTopics: Record<string, number>;
    engagedAuthors: Record<string, number>;
    preferredCategories: Record<string, number>;
    onboardingGoals: string[];
};

type FeedRankRequest = {
    userId?: string;
    posts: FeedPostPayload[];
    interests: FeedInterestsPayload;
    followingIds: string[];
    sessionCardsServed: number;
    sessionCap: number;
};

type ContextPreferences = {
    disabled: boolean;
    mutedTopicIds: string[];
    mutedTypes: string[];
    hiddenContextIds: string[];
};

type UserContext = {
    churchId?: string;
    city?: string;
    communityId?: string;
    interests: string[];
    scriptureTopics: string[];
    prayerInterests: string[];
};

type AmenFeedContextType =
    | "inConversation"
    | "scriptureFocus"
    | "sharedInYourCircles"
    | "resonatingNearby"
    | "bereanInsight"
    | "churchPulse"
    | "gentleFollowUp"
    | "livePrayerMoment"
    | "communityQuestion"
    | "relevantNow";

type AmenFeedContextDestinationType =
    | "topicFeed"
    | "scriptureCluster"
    | "churchPulse"
    | "prayerMoment"
    | "bereanInsight"
    | "postThread"
    | "whyThisAppeared"
    | "none";

type AmenFeedContextPayload = {
    contextId: string;
    contextType: AmenFeedContextType;
    contextTitle: string;
    contextReason: string;
    contextConfidence: number;
    contextPriority: number;
    contextDestinationType: AmenFeedContextDestinationType;
    contextDestinationId?: string | null;
    contextTopicId?: string | null;
    contextVerseRef?: string | null;
    contextChurchId?: string | null;
    contextCommunityId?: string | null;
    contextExpiresAt: string;
    contextIsSensitive: boolean;
    contextIsDismissible: boolean;
    contextAnalyticsId: string;
};

type RankedFeedWithContextResponse = {
    rankedIds: string[];
    sessionCapRemaining: number;
    sessionExhausted: boolean;
    contextsByPostId: Record<string, AmenFeedContextPayload>;
};

function requireAuth(request: { auth?: { uid?: string } }): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function clamp(value: number, min = 0, max = 1): number {
    return Math.max(min, Math.min(max, value));
}

function normalizeTopicKey(raw: string | null | undefined): string | null {
    const trimmed = raw?.trim();
    if (!trimmed) return null;
    return trimmed.toLowerCase().replace(/\s+/g, "_");
}

function normalizeTitle(raw: string): string {
    return raw.replace(/\s+/g, " ").trim();
}

function scoreMomentum(post: FeedPostPayload, ageHours: number): number {
    const engagement = Math.min(post.amenCount * 0.02 + post.commentCount * 0.04, 1);
    const freshness = clamp(1 - ageHours / 72);
    return clamp(engagement * 0.6 + freshness * 0.4);
}

function scoreCommunity(post: FeedPostPayload, request: FeedRankRequest, userContext: UserContext): number {
    let score = 0;
    if (request.followingIds.includes(post.authorId)) score += 0.45;
    if (post.churchId && userContext.churchId && post.churchId === userContext.churchId) score += 0.3;
    if (post.communityId && userContext.communityId && post.communityId === userContext.communityId) score += 0.2;
    return clamp(score);
}

function scoreScripture(post: FeedPostPayload, userContext: UserContext): number {
    const verseRef = post.verseRef?.trim() ?? "";
    const scriptureTopics = userContext.scriptureTopics.map((value) => value.toLowerCase());
    const content = post.content.toLowerCase();
    let score = verseRef ? 0.65 : 0;
    if (scriptureTopics.some((topic) => topic && content.includes(topic))) score += 0.2;
    if (/\bromans\b|\bpsalm\b|\bjohn\b|\bhebrews\b|\bcorinthians\b/.test(content)) score += 0.15;
    return clamp(score);
}

function scorePersonalRelevance(post: FeedPostPayload, request: FeedRankRequest, userContext: UserContext): number {
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
        ...userContext.interests,
        ...userContext.prayerInterests,
        ...request.interests.onboardingGoals,
    ].map((value) => value.toLowerCase());
    if (allInterestTerms.some((term) => term && content.includes(term))) {
        score += 0.2;
    }
    return clamp(score);
}

function scoreTrust(post: FeedPostPayload): number {
    if (post.lowTrustAuthor || post.flaggedForReview || post.removed) {
        return 0;
    }
    const baitPattern = /\bviral\b|\btrending\b|\bbreaking\b|\bexploding\b|\bhot topic\b/i.test(post.content);
    return baitPattern ? 0.25 : 1;
}

function classifySensitive(content: string): boolean {
    return /\bpolitics\b|\babuse\b|\bsuicide\b|\bwar\b|\bviolence\b|\bchurch hurt\b/i.test(content);
}

function chooseContextType(
    post: FeedPostPayload,
    scores: {
        momentumScore: number;
        communityScore: number;
        scriptureScore: number;
        personalRelevanceScore: number;
    },
): AmenFeedContextType | null {
    if (post.lowTrustAuthor || post.flaggedForReview || post.removed) return null;
    if (post.linkedPrayerRequestId && scores.momentumScore >= 0.8) return "livePrayerMoment";
    if ((post.verseRef || post.category === "scripture") && scores.scriptureScore >= 0.72) return "scriptureFocus";
    if (post.churchId && scores.communityScore >= 0.72) return "churchPulse";
    if (scores.communityScore >= 0.74 && post.communityId) return "sharedInYourCircles";
    if (scores.personalRelevanceScore >= 0.78 && scores.scriptureScore >= 0.55) return "bereanInsight";
    if (scores.momentumScore >= 0.76 && post.commentCount >= 3) return "communityQuestion";
    if (scores.communityScore >= 0.68) return "resonatingNearby";
    if (scores.personalRelevanceScore >= 0.7) return "gentleFollowUp";
    if (scores.momentumScore >= 0.72) return "inConversation";
    if (scores.personalRelevanceScore >= 0.64) return "relevantNow";
    return null;
}

function destinationForType(type: AmenFeedContextType): AmenFeedContextDestinationType {
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

function prefixForType(type: AmenFeedContextType, sensitive: boolean): string {
    if (sensitive) {
        switch (type) {
        case "scriptureFocus":
            return "Scripture focus";
        case "churchPulse":
            return "Community reflection";
        case "livePrayerMoment":
        case "gentleFollowUp":
            return "Prayer focus";
        default:
            return "Current conversation";
        }
    }
    switch (type) {
    case "inConversation":
        return "In conversation";
    case "scriptureFocus":
        return "Scripture focus";
    case "sharedInYourCircles":
        return "Shared in your circles";
    case "resonatingNearby":
        return "Resonating nearby";
    case "bereanInsight":
        return "Berean insight";
    case "churchPulse":
        return "Church pulse";
    case "gentleFollowUp":
        return "Gentle follow-up";
    case "livePrayerMoment":
        return "Live prayer moment";
    case "communityQuestion":
        return "Community question";
    case "relevantNow":
        return "Relevant now";
    }
}

function confidenceThresholdForType(type: AmenFeedContextType, sensitive: boolean): number {
    if (sensitive) return 0.86;
    if (type === "livePrayerMoment") return 0.8;
    if (type === "bereanInsight") return 0.78;
    return 0.72;
}

function reasonForType(type: AmenFeedContextType, post: FeedPostPayload): string {
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
        return `You’re seeing this because ${normalizeTitle(post.topicTag ?? "this topic")} is drawing thoughtful conversation right now.`;
    }
}

function buildContextTitle(post: FeedPostPayload, type: AmenFeedContextType): string {
    if (type === "scriptureFocus" && post.verseRef) return normalizeTitle(post.verseRef);
    const fallback = post.topicTag ?? post.category ?? "Reflection";
    return normalizeTitle(fallback);
}

function buildExpiration(type: AmenFeedContextType): string {
    const hours = CONTEXT_EXPIRATION_HOURS[type] ?? 24;
    return new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
}

export function computeContextScore(post: FeedPostPayload, request: FeedRankRequest, userContext: UserContext) {
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

export function buildContextPayload(post: FeedPostPayload, request: FeedRankRequest, userContext: UserContext): AmenFeedContextPayload | null {
    const scores = computeContextScore(post, request, userContext);
    const contextType = chooseContextType(post, scores);
    if (!contextType) return null;

    const title = buildContextTitle(post, contextType);
    if (!title || title.length < 3) return null;

    const sensitive = classifySensitive(`${post.content} ${title}`);
    const threshold = confidenceThresholdForType(contextType, sensitive);
    if (scores.contextScore < threshold) return null;
    if (sensitive && !["scriptureFocus", "churchPulse", "livePrayerMoment", "gentleFollowUp", "inConversation"].includes(contextType)) {
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
        contextDestinationId: post.linkedPrayerRequestId ?? post.topicTag ?? post.communityId ?? post.churchId ?? null,
        contextTopicId: normalizeTopicKey(post.topicTag),
        contextVerseRef: post.verseRef ?? null,
        contextChurchId: post.churchId ?? null,
        contextCommunityId: post.communityId ?? null,
        contextExpiresAt: buildExpiration(contextType),
        contextIsSensitive: sensitive,
        contextIsDismissible: true,
        contextAnalyticsId: `ctx_${post.id}_${contextType}`,
    };
}

export function validateFeedbackAction(action: string): boolean {
    return ALLOWED_FEEDBACK_ACTIONS.has(action);
}

async function loadUserContext(uid: string): Promise<UserContext> {
    const [userDoc, prefsDoc] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("userFeedPrefs").doc(uid).get(),
    ]);
    const user = userDoc.data() ?? {};
    const prefs = prefsDoc.data() ?? {};

    return {
        churchId: typeof user.churchId === "string" ? user.churchId : undefined,
        city: typeof user.city === "string" ? user.city : undefined,
        communityId: typeof user.communityId === "string" ? user.communityId : undefined,
        interests: Array.isArray(user.interests) ? user.interests.filter((value): value is string => typeof value === "string") : [],
        scriptureTopics: Array.isArray(user.scriptureTopics) ? user.scriptureTopics.filter((value): value is string => typeof value === "string") : [],
        prayerInterests: Array.isArray(prefs.prayerInterests) ? prefs.prayerInterests.filter((value): value is string => typeof value === "string") : [],
    };
}

function normalizePosts(raw: unknown): FeedPostPayload[] {
    if (!Array.isArray(raw)) return [];
    return raw.flatMap((item) => {
        if (!item || typeof item !== "object") return [];
        const candidate = item as Partial<FeedPostPayload>;
        if (typeof candidate.id !== "string" || typeof candidate.authorId !== "string" || typeof candidate.content !== "string" || typeof candidate.category !== "string" || typeof candidate.createdAt !== "number") {
            return [];
        }
        return [{
            id: candidate.id,
            authorId: candidate.authorId,
            content: candidate.content,
            category: candidate.category,
            topicTag: candidate.topicTag ?? null,
            amenCount: typeof candidate.amenCount === "number" ? candidate.amenCount : 0,
            commentCount: typeof candidate.commentCount === "number" ? candidate.commentCount : 0,
            createdAt: candidate.createdAt,
            verseRef: candidate.verseRef ?? null,
            churchId: candidate.churchId ?? null,
            communityId: candidate.communityId ?? null,
            linkedPrayerRequestId: candidate.linkedPrayerRequestId ?? null,
            lowTrustAuthor: candidate.lowTrustAuthor === true,
            flaggedForReview: candidate.flaggedForReview === true,
            removed: candidate.removed === true,
        }];
    });
}

function buildRankedFeedResponse(request: FeedRankRequest, userContext: UserContext): RankedFeedWithContextResponse {
    const normalizedPosts = normalizePosts(request.posts);
    const contextsByPostId: Record<string, AmenFeedContextPayload> = {};

    const ranked = normalizedPosts
        .map((post) => {
            const scores = computeContextScore(post, request, userContext);
            const context = buildContextPayload(post, request, userContext);
            if (context) {
                contextsByPostId[post.id] = context;
            }
            const engagementScore = clamp(post.amenCount * 0.015 + post.commentCount * 0.03);
            const recencyScore = clamp(1 - ((Date.now() / 1000 - post.createdAt) / (72 * 3600)));
            const finalScore = scores.contextScore * 0.55 + engagementScore * 0.2 + recencyScore * 0.25;
            return { postId: post.id, finalScore };
        })
        .sort((lhs, rhs) => rhs.finalScore - lhs.finalScore);

    const rankedIds = ranked.map((item) => item.postId);
    const sessionCapRemaining = Math.max(0, request.sessionCap - request.sessionCardsServed - rankedIds.length);

    return {
        rankedIds,
        sessionCapRemaining,
        sessionExhausted: sessionCapRemaining === 0,
        contextsByPostId,
    };
}

export const computeFeedContextLabels = onCall(async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Partial<FeedRankRequest>;
    const normalizedRequest: FeedRankRequest = {
        userId: uid,
        posts: normalizePosts(data.posts),
        interests: data.interests ?? {
            engagedTopics: {},
            engagedAuthors: {},
            preferredCategories: {},
            onboardingGoals: [],
        },
        followingIds: Array.isArray(data.followingIds) ? data.followingIds.filter((value): value is string => typeof value === "string") : [],
        sessionCardsServed: typeof data.sessionCardsServed === "number" ? data.sessionCardsServed : 0,
        sessionCap: typeof data.sessionCap === "number" ? data.sessionCap : 25,
    };

    const userContext = await loadUserContext(uid);
    return {
        contextsByPostId: Object.fromEntries(
            normalizedRequest.posts
                .map((post) => [post.id, buildContextPayload(post, normalizedRequest, userContext)] as const)
                .filter((entry): entry is [string, AmenFeedContextPayload] => entry[1] !== null),
        ),
    };
});

export const attachFeedContextToRankedPosts = onCall(async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Partial<FeedRankRequest>;
    const normalizedRequest: FeedRankRequest = {
        userId: uid,
        posts: normalizePosts(data.posts),
        interests: data.interests ?? {
            engagedTopics: {},
            engagedAuthors: {},
            preferredCategories: {},
            onboardingGoals: [],
        },
        followingIds: Array.isArray(data.followingIds) ? data.followingIds.filter((value): value is string => typeof value === "string") : [],
        sessionCardsServed: typeof data.sessionCardsServed === "number" ? data.sessionCardsServed : 0,
        sessionCap: typeof data.sessionCap === "number" ? data.sessionCap : 25,
    };

    if (normalizedRequest.posts.length === 0) {
        return {
            rankedIds: [],
            sessionCapRemaining: normalizedRequest.sessionCap,
            sessionExhausted: false,
            contextsByPostId: {},
        } satisfies RankedFeedWithContextResponse;
    }

    const userContext = await loadUserContext(uid);
    return buildRankedFeedResponse(normalizedRequest, userContext);
});

export const updateUserContextLabelPreferences = onCall(async (request) => {
    const uid = requireAuth(request);
    const data = (request.data ?? {}) as Partial<ContextPreferences>;
    const payload = {
        disabled: data.disabled === true,
        mutedTopicIds: Array.isArray(data.mutedTopicIds) ? data.mutedTopicIds.filter((value): value is string => typeof value === "string") : [],
        mutedTypes: Array.isArray(data.mutedTypes) ? data.mutedTypes.filter((value): value is string => typeof value === "string") : [],
        hiddenContextIds: Array.isArray(data.hiddenContextIds) ? data.hiddenContextIds.filter((value): value is string => typeof value === "string") : [],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users")
        .doc(uid)
        .collection("feedPreferences")
        .doc("contextLabels")
        .set(payload, { merge: true });

    return { success: true };
});

export const trackContextLabelEvent = onCall(async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const action = typeof data.action === "string" ? data.action : "";
    if (!validateFeedbackAction(action)) {
        throw new HttpsError("invalid-argument", "Unsupported context feedback action.");
    }
    if (typeof data.userId === "string" && data.userId !== uid) {
        throw new HttpsError("permission-denied", "Cannot write feedback for another user.");
    }

    await db.collection("users")
        .doc(uid)
        .collection("feedPreferences")
        .doc("contextLabelEvents")
        .collection("events")
        .add({
            uid,
            action,
            contextId: typeof data.contextId === "string" ? data.contextId : "",
            topicId: typeof data.topicId === "string" ? data.topicId : null,
            contextType: typeof data.contextType === "string" ? data.contextType : "",
            postId: typeof data.postId === "string" ? data.postId : "",
            confidence: typeof data.confidence === "number" ? data.confidence : null,
            destinationType: typeof data.destinationType === "string" ? data.destinationType : null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

    return { success: true };
});

export const suppressContextLabelForUser = onCall(async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;
    const action = typeof data.action === "string" ? data.action : "";
    if (!validateFeedbackAction(action)) {
        throw new HttpsError("invalid-argument", "Unsupported context feedback action.");
    }

    const ref = db.collection("users").doc(uid).collection("feedPreferences").doc("contextLabels");
    const snapshot = await ref.get();
    const existing = (snapshot.data() ?? {}) as Partial<ContextPreferences>;
    const hiddenContextIds = new Set(existing.hiddenContextIds ?? []);
    const mutedTopicIds = new Set(existing.mutedTopicIds ?? []);
    const mutedTypes = new Set(existing.mutedTypes ?? []);
    let disabled = existing.disabled === true;

    if (typeof data.contextId === "string" && ["dismiss", "show_less"].includes(action)) {
        hiddenContextIds.add(data.contextId);
    }
    if (action === "mute_topic" && typeof data.topicId === "string") {
        mutedTopicIds.add(data.topicId);
    }
    if (action === "mute_type" && typeof data.contextType === "string") {
        mutedTypes.add(data.contextType);
    }
    if (action === "hide_all") {
        disabled = true;
    }

    await ref.set({
        disabled,
        mutedTopicIds: Array.from(mutedTopicIds),
        mutedTypes: Array.from(mutedTypes),
        hiddenContextIds: Array.from(hiddenContextIds),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { success: true };
});
