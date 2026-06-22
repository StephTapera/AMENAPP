import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();
type CallableAuthContext = {
    auth?: { uid: string };
    app?: unknown;
};

function requireAuth(context: CallableAuthContext) {
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Auth required");
    }
    return context.auth.uid;
}

function requireAppCheck(context: CallableAuthContext) {
    if (!context.app) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
}

async function verifyPostAuthor(uid: string, postId: string): Promise<void> {
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) {
        throw new HttpsError("not-found", "Content not found.");
    }
    if (postDoc.get("authorId") !== uid) {
        throw new HttpsError("permission-denied", "Only the content author may perform this action.");
    }
}

async function verifyPostAccessible(uid: string, postId: string): Promise<admin.firestore.DocumentData> {
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) {
        throw new HttpsError("not-found", "Content not found.");
    }
    const data = postDoc.data()!;
    const visibility = String(data["visibility"] ?? "everyone");
    const authorId = String(data["authorId"] ?? "");
    if (authorId !== uid && visibility !== "everyone") {
        throw new HttpsError("permission-denied", "Content not accessible.");
    }
    return data;
}

function asSafeString(value: unknown, maxLength = 280): string {
    return String(value ?? "").trim().slice(0, maxLength);
}

function buildComposeIntent(text: string) {
    const lower = text.toLowerCase();
    const contains = (...patterns: string[]) => patterns.some((pattern) => lower.includes(pattern));

    const intentType =
        contains("pray for", "please pray", "need prayer") ? "prayer" :
            contains("god brought me", "i was lost", "testimony", "grateful") ? "testimony" :
                contains("forgive me", "repent", "i sinned") ? "confession" :
                    contains("psalm ", "john ", "romans ", "scripture") ? "scripture_reflection" :
                        contains("should i", "what should i do", "?") ? "question" :
                            contains("you should", "you always", "ashamed", "fake christian") ? "correction" :
                                contains("angry", "i hate", "venting") ? "venting" :
                                    contains("encourage", "god loves you", "keep going") ? "encouragement" :
                                        "unknown";

    const toneRisk =
        contains("ashamed", "fake christian", "worthless", "disgusting", "shut up", "idiot", "you always", "you never")
            ? "amber"
            : contains("if you loved god", "if you were really a christian", "manipulate")
                ? "amber"
                : "green";

    const suggestionSummary =
        toneRisk === "amber"
            ? "Consider softening this before sending."
            : intentType === "scripture_reflection"
                ? "Add scripture context if that would help your readers."
                : intentType === "prayer"
                    ? "You could turn this into a direct prayer."
                    : "No suggestion needed.";

    return {
        intentType,
        toneRisk,
        suggestionSummary,
        rewriteAvailable: toneRisk === "amber",
    };
}

export function scorePriorityItem(item: {
    urgencyScore: number;
    relationshipScore: number;
    depthScore: number;
    followUpNeedScore: number;
    scriptureRelevanceScore: number;
    recencyScore: number;
}): number {
    return item.urgencyScore * 0.30 +
        item.relationshipScore * 0.20 +
        item.depthScore * 0.20 +
        item.followUpNeedScore * 0.15 +
        item.scriptureRelevanceScore * 0.10 +
        item.recencyScore * 0.05;
}

export function summarizeSilentReactions(reactionTypes: string[]): { summaryText: string; reactionTypes: string[] } {
    const unique = Array.from(new Set(reactionTypes));
    const phrases: string[] = [];
    if (unique.includes("prayed")) phrases.push("Someone prayed with this");
    if (unique.includes("encouraged")) phrases.push("Someone found this encouraging");
    if (unique.includes("reflected")) phrases.push("This helped someone reflect");
    if (unique.includes("grateful")) phrases.push("Someone felt grateful for this");
    if (unique.includes("stoodWithYou")) phrases.push("Someone quietly stood with you");
    return {
        summaryText: phrases.join(" • "),
        reactionTypes: unique,
    };
}

export const updatePresenceState = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const selectedState = asSafeString(data?.selectedState, 32);
    const visibility = asSafeString(data?.visibility, 32);
    const allowedStates = ["reflecting", "praying", "reading", "resting", "seeking", "available"];
    // "mutuals" is retained as a stored value for migration but new writes are restricted to
    // private_only or everyone until mutual-relationship verification is implemented server-side.
    const allowedVisibility = ["private_only", "everyone"];

    if (!allowedStates.includes(selectedState) || !allowedVisibility.includes(visibility)) {
        throw new HttpsError("invalid-argument", "Invalid presence state.");
    }

    await db.collection("presence_states").doc(uid).set({
        userId: uid,
        selectedState,
        visibility,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true };
});

export const addSilentReaction = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const sourceId = asSafeString(data?.sourceId, 120);
    const sourceType = asSafeString(data?.sourceType, 32);
    const reactionType = asSafeString(data?.reactionType, 32);
    const allowedReactions = ["prayed", "encouraged", "reflected", "grateful", "stoodWithYou"];
    const allowedSourceTypes = ["post", "comment"];

    if (!sourceId || !allowedSourceTypes.includes(sourceType) || !allowedReactions.includes(reactionType)) {
        throw new HttpsError("invalid-argument", "Invalid silent reaction payload.");
    }

    // Verify the source post exists and caller is not the author (no self-reactions)
    if (sourceType === "post") {
        const postDoc = await db.collection("posts").doc(sourceId).get();
        if (!postDoc.exists) {
            throw new HttpsError("not-found", "Content not found.");
        }
        if (postDoc.get("authorId") === uid) {
            throw new HttpsError("permission-denied", "Cannot react to your own content.");
        }
    }

    const reactionId = `${uid}_${sourceType}_${sourceId}_${reactionType}`;
    await db.collection("silent_reactions").doc(reactionId).set({
        sourceId,
        sourceType,
        userId: uid,
        reactionType,
        visibilityMode: "private_summary",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, reactionId };
});

export const getSilentReactionSummary = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const sourceId = asSafeString(data?.sourceId, 120);
    const sourceType = asSafeString(data?.sourceType, 32);
    if (!sourceId || !sourceType) {
        throw new HttpsError("invalid-argument", "Invalid reaction summary request.");
    }

    // Only the content author may see aggregate reaction summaries.
    if (sourceType === "post") {
        await verifyPostAuthor(uid, sourceId);
    } else {
        // Author verification for other sourceTypes (comments etc.) is not yet implemented.
        // Return empty rather than leaking data to non-authors.
        return { summaryText: "", reactionTypes: [] };
    }

    const snapshot = await db.collection("silent_reactions")
        .where("sourceId", "==", sourceId)
        .where("sourceType", "==", sourceType)
        .limit(50)
        .get();

    const summary = summarizeSilentReactions(snapshot.docs.map((doc) => String(doc.get("reactionType") ?? "")));
    return summary;
});

export const checkComposeIntent = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const text = asSafeString(data?.text, 1000);
    const sourceSurface = asSafeString(data?.sourceSurface, 64);
    if (!text || !sourceSurface) {
        throw new HttpsError("invalid-argument", "Text and source surface are required.");
    }

    const result = buildComposeIntent(text);
    const checkId = db.collection("intent_compose_checks").doc().id;

    await db.collection("intent_compose_checks").doc(checkId).set({
        userId: uid,
        sourceSurface,
        intentType: result.intentType,
        toneRisk: result.toneRisk,
        suggestionSummary: result.suggestionSummary,
        rewriteAvailable: result.rewriteAvailable,
        textLength: text.length,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return result;
});

export const getSpiritualPriorityInbox = onCall({ enforceAppCheck: true }, async (request) => {
    const _data = request.data as any;
    const data = _data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    // Compute priority items from actual user content — unanswered prayers and active threads.
    // No pre-computed collection is required; results are built on-demand from real post data.
    const [prayerSnap, threadSnap] = await Promise.all([
        db.collection("posts")
            .where("authorId", "==", uid)
            .where("category", "==", "prayer")
            .orderBy("createdAt", "desc")
            .limit(15)
            .get(),
        db.collection("posts")
            .where("authorId", "==", uid)
            .orderBy("createdAt", "desc")
            .limit(15)
            .get(),
    ]);

    const items: Array<{ id: string; title: string; subtitle: string; reasonChips: string[]; priorityScore: number }> = [];
    const addedIds = new Set<string>();

    for (const doc of prayerSnap.docs) {
        if (doc.get("prayerStatus") === "answered" || doc.get("isAnsweredPrayer")) continue;
        const content = asSafeString(doc.get("content") ?? "", 100);
        items.push({ id: doc.id, title: content || "Prayer request", subtitle: "This prayer may be worth following up on.", reasonChips: ["Prayer follow-up", "Unresolved"], priorityScore: 0.85 });
        addedIds.add(doc.id);
    }

    for (const doc of threadSnap.docs) {
        if (addedIds.has(doc.id)) continue;
        const threadPostCount = Number(doc.get("threadPostCount") ?? 0);
        if (threadPostCount < 2) continue;
        const content = asSafeString(doc.get("content") ?? "", 100);
        items.push({ id: doc.id, title: content || "Active thread", subtitle: "This conversation is still unfolding.", reasonChips: ["Living thread", "Ongoing"], priorityScore: 0.65 });
        addedIds.add(doc.id);
    }

    items.sort((a, b) => b.priorityScore - a.priorityScore);
    return { items: items.slice(0, 20) };
});

export const evaluateThreadLifecycle = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const threadId = asSafeString(data?.threadId, 120);
    if (!threadId) {
        throw new HttpsError("invalid-argument", "threadId is required.");
    }

    // Compute lifecycle from actual thread posts — no pre-computed collection required.
    const threadSnap = await db.collection("posts")
        .where("threadId", "==", threadId)
        .orderBy("createdAt", "desc")
        .limit(20)
        .get();

    if (threadSnap.empty) {
        throw new HttpsError("not-found", "Thread not found.");
    }

    const firstDoc = threadSnap.docs[0];
    if (firstDoc.get("authorId") !== uid) {
        throw new HttpsError("permission-denied", "Thread not accessible.");
    }

    const hasAnswered = threadSnap.docs.some(d => d.get("prayerStatus") === "answered" || d.get("isAnsweredPrayer"));
    const hasPrayer = threadSnap.docs.some(d => d.get("category") === "prayer");
    const postCount = threadSnap.docs.length;

    const lifecycleState = hasAnswered ? "answered" : hasPrayer ? "followUpNeeded" : postCount > 1 ? "active" : "dormant";
    const resurfacingReason = hasAnswered ? "This prayer was answered."
        : hasPrayer ? "This prayer may be worth revisiting."
            : postCount > 1 ? "This conversation is still unfolding."
                : "This thread has gone quiet.";

    return {
        threadId,
        lifecycleState,
        resurfacingReason,
        postCount,
        lastActivityAt: firstDoc.get("createdAt"),
    };
});

export const getContextualMemoryLayer = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const sourceId = asSafeString(data?.sourceId, 120);
    if (!sourceId) {
        throw new HttpsError("invalid-argument", "sourceId is required.");
    }

    // Verify the post exists and caller can access it before returning any related data.
    const postData = await verifyPostAccessible(uid, sourceId);

    const verseReference = postData["verseReference"] as string | undefined;
    const linkedPrayerRequestId = postData["linkedPrayerRequestId"] as string | undefined;
    const threadId = postData["threadId"] as string | undefined;

    const scriptureRefs: string[] = verseReference ? [verseReference] : [];
    const relatedPrayerIds: string[] = linkedPrayerRequestId ? [linkedPrayerRequestId] : [];
    let relatedPostIds: string[] = [];

    if (threadId) {
        const threadSnap = await db.collection("posts")
            .where("threadId", "==", threadId)
            .limit(5)
            .get();
        relatedPostIds = threadSnap.docs.filter(d => d.id !== sourceId).map(d => d.id);
    }

    return { scriptureRefs, relatedPostIds, relatedPrayerIds, savedNoteIds: [], bereanInsightIds: [] };
});

export const summonThreads = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const query = asSafeString(data?.query, 240).toLowerCase();
    if (!query) {
        throw new HttpsError("invalid-argument", "query is required.");
    }

    // Search actual user posts — prayers, reflections, and threads — for natural-language queries.
    const snapshot = await db.collection("posts")
        .where("authorId", "==", uid)
        .orderBy("createdAt", "desc")
        .limit(50)
        .get();

    const tokens = query.split(/\s+/).filter(t => t.length > 2);
    const results = snapshot.docs
        .filter((doc) => {
            const content = String(doc.get("content") ?? "").toLowerCase();
            const category = String(doc.get("category") ?? "").toLowerCase();
            const verse = String(doc.get("verseReference") ?? "").toLowerCase();
            const text = `${category} ${content} ${verse}`;
            return tokens.some(token => text.includes(token));
        })
        .map((doc) => {
            const content = asSafeString(doc.get("content") ?? "", 80);
            const category = String(doc.get("category") ?? "post");
            const isPrayer = category === "prayer";
            return {
                id: doc.id,
                title: content || "Post",
                subtitle: isPrayer ? "Prayer request" : category,
                reason: isPrayer ? "Matched a prayer-related phrase." : "Matched your natural-language query.",
                sourceType: "post",
            };
        })
        .slice(0, 20);

    return { results };
});
