import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();
const REGION = "us-central1";
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

type CallableRequest = {
    auth?: { uid?: string };
    app?: { appId?: string };
    data?: Record<string, unknown>;
};

type LiveStateValue = "live" | "upcoming" | "closed" | "quiet" | "unknown";
type SmartActionValue = "joinLive" | "checkIn" | "planVisit" | "askBerean" | "saveChurch";

function requireAuth(request: CallableRequest): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function requireAppCheck(request: CallableRequest): void {
    if (IS_EMULATOR) return;
    if (!request.app?.appId) {
        throw new HttpsError("failed-precondition", "App Check token required.");
    }
}

function readChurchId(request: CallableRequest): string {
    const churchId = String(request.data?.churchId ?? "").trim();
    if (!churchId) {
        throw new HttpsError("invalid-argument", "churchId is required.");
    }
    return churchId;
}

async function loadChurchSnapshot(churchId: string): Promise<FirebaseFirestore.DocumentSnapshot> {
    const snapshot = await db.collection("churches").doc(churchId).get();
    if (!snapshot.exists) {
        throw new HttpsError("not-found", "Church not found.");
    }
    return snapshot;
}

function normalizedString(value: unknown): string {
    return String(value ?? "").trim();
}

function normalizedList(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value.map((item) => normalizedString(item)).filter(Boolean);
}

function confidenceForKnownFields(fields: Array<string | null | undefined>): number {
    const knownCount = fields.filter((value) => Boolean(normalizedString(value))).length;
    return Math.max(0.15, Math.min(0.95, knownCount / Math.max(fields.length, 1)));
}

function fallbackLiveState(churchData: FirebaseFirestore.DocumentData): {
    state: LiveStateValue;
    title: string;
    description: string;
    livestreamUrl: string | null;
    confidence: number;
} {
    const serviceTimes = Array.isArray(churchData.serviceTimes) ? churchData.serviceTimes : [];
    const livestreamUrl = normalizedString(churchData.livestreamUrl || churchData.livestreamURL) || null;

    if (serviceTimes.length > 0) {
        logger.warn("refreshChurchLiveState: no live signal — falling back to service schedule", {
            hasLivestream: !!livestreamUrl,
        });
        return {
            state: "upcoming",
            title: "Service schedule available",
            description: livestreamUrl
                ? "Next service timing may be available. Livestream link is listed."
                : "Service times are listed, but a current live signal is not confirmed.",
            livestreamUrl,
            confidence: livestreamUrl ? 0.58 : 0.44,
        };
    }

    logger.warn("refreshChurchLiveState: no live signal and no service times — returning unknown");
    return {
        state: "unknown",
        title: "Not live right now",
        description: "Next service unknown.",
        livestreamUrl,
        confidence: livestreamUrl ? 0.34 : 0.18,
    };
}

function fallbackExperienceSummary(churchData: FirebaseFirestore.DocumentData) {
    const accessibility = normalizedList(churchData.accessibility).join(", ");
    const denomination = normalizedString(churchData.denomination);
    const knownFieldCount = [accessibility, denomination].filter(Boolean).length;
    if (knownFieldCount === 0) {
        logger.warn("generateChurchExperienceSummary: no church profile fields available — low confidence fallback");
    }
    return {
        parking: "Not confirmed yet",
        bestArrivalTime: "Not confirmed yet",
        entrance: "Not confirmed yet",
        serviceLength: "Not confirmed yet",
        worshipStyle: denomination || "Not confirmed yet",
        kidsMinistry: "Not confirmed yet",
        accessibility: accessibility || "Not confirmed yet",
        translation: "Not confirmed yet",
        quietSpace: "Not confirmed yet",
        firstTimeFlow: "Not confirmed yet",
        confidence: confidenceForKnownFields([accessibility, denomination]),
    };
}

function fallbackFitScore(userData: FirebaseFirestore.DocumentData | undefined, churchData: FirebaseFirestore.DocumentData) {
    const savedChurches = normalizedList(userData?.savedChurches);
    const reasons: string[] = [];

    if (savedChurches.length > 0) {
        reasons.push("Based on churches you saved and revisited.");
    }
    if (normalizedString(churchData.denomination)) {
        reasons.push("Uses verified church profile details where available.");
    }
    if (reasons.length === 0) {
        logger.warn("calculateChurchFitScore: no user preference data — returning zero score");
        reasons.push("Not enough data yet.");
    }

    return {
        score: savedChurches.length > 0 ? 72 : 0,
        confidence: savedChurches.length > 0 ? 0.46 : 0.14,
        reasons,
        disclaimers: [
            "Preference alignment only.",
            "Not a rating of spiritual quality.",
        ],
    };
}

function resolvePrimaryAction(input: {
    liveState?: LiveStateValue;
    livestreamUrl?: string | null;
    fitScore?: number;
    distanceMiles?: number | null;
}): { primaryAction: SmartActionValue; secondaryActions: SmartActionValue[]; reason: string } {
    if (input.liveState === "live" && input.livestreamUrl) {
        return {
            primaryAction: "joinLive",
            secondaryActions: ["planVisit", "saveChurch"],
            reason: "Live signal and livestream link are both available.",
        };
    }
    if ((input.distanceMiles ?? Number.POSITIVE_INFINITY) <= 10) {
        return {
            primaryAction: "checkIn",
            secondaryActions: ["planVisit", "saveChurch"],
            reason: "The church appears to be nearby.",
        };
    }
    if (input.liveState === "upcoming") {
        return {
            primaryAction: "planVisit",
            secondaryActions: ["askBerean", "saveChurch"],
            reason: "A service schedule is available soon.",
        };
    }
    if ((input.fitScore ?? 0) >= 70) {
        return {
            primaryAction: "planVisit",
            secondaryActions: ["askBerean", "saveChurch"],
            reason: "Preference alignment may be strong enough to plan a first visit.",
        };
    }
    return {
        primaryAction: "askBerean",
        secondaryActions: ["saveChurch", "planVisit"],
        reason: "There is not enough verified context to recommend a stronger action yet.",
    };
}

export const refreshChurchLiveState = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    logger.info("refreshChurchLiveState: called", { churchId });

    const churchSnapshot = await loadChurchSnapshot(churchId);
    const churchData = churchSnapshot.data() ?? {};

    const result = fallbackLiveState(churchData);
    const writePayload = {
        state: result.state,
        title: result.title,
        description: result.description,
        startsAt: null,
        endsAt: null,
        livestreamUrl: result.livestreamUrl,
        attendanceSignal: null,
        atmosphereTags: [],
        confidence: result.confidence,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
        await churchSnapshot.ref.collection("live_state").doc("current").set(writePayload, { merge: true });
        logger.info("refreshChurchLiveState: Firestore write succeeded", { churchId, state: result.state });
    } catch (err) {
        logger.error("refreshChurchLiveState: Firestore write failed", { churchId, err });
        throw new HttpsError("internal", "Failed to update live state.");
    }

    return {
        churchId,
        state: result.state,
        title: result.title,
        description: result.description,
        startsAt: null,
        endsAt: null,
        livestreamUrl: result.livestreamUrl,
        attendanceSignal: null,
        atmosphereTags: [],
        confidence: result.confidence,
        updatedAt: null,
    };
});

export const generateChurchExperienceSummary = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    logger.info("generateChurchExperienceSummary: called", { churchId });

    const churchSnapshot = await loadChurchSnapshot(churchId);
    const churchData = churchSnapshot.data() ?? {};

    const summary = fallbackExperienceSummary(churchData);
    const writePayload = {
        ...summary,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
        await churchSnapshot.ref.collection("experience_summary").doc("current").set(writePayload, { merge: true });
        logger.info("generateChurchExperienceSummary: Firestore write succeeded", { churchId, confidence: summary.confidence });
    } catch (err) {
        logger.error("generateChurchExperienceSummary: Firestore write failed", { churchId, err });
        throw new HttpsError("internal", "Failed to update experience summary.");
    }

    return { churchId, ...summary, updatedAt: null };
});

export const calculateChurchFitScore = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const uid = requireAuth(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);
    logger.info("calculateChurchFitScore: called", { uid, churchId });

    const [churchSnapshot, userSnapshot] = await Promise.all([
        loadChurchSnapshot(churchId),
        db.collection("users").doc(uid).get(),
    ]);

    const fitScore = fallbackFitScore(userSnapshot.data(), churchSnapshot.data() ?? {});
    const writePayload = {
        ...fitScore,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
        await db.collection("users").doc(uid).collection("church_fit").doc(churchId).set(writePayload, { merge: true });
        logger.info("calculateChurchFitScore: Firestore write succeeded", { uid, churchId, score: fitScore.score });
    } catch (err) {
        logger.error("calculateChurchFitScore: Firestore write failed", { uid, churchId, err });
        throw new HttpsError("internal", "Failed to update fit score.");
    }

    return { churchId, ...fitScore, updatedAt: null };
});

export const resolveChurchSmartAction = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const uid = requireAuth(request as CallableRequest);
    const churchId = readChurchId(request as CallableRequest);

    // Validate optional distanceMiles: must be a non-negative finite number if provided.
    const rawDistance = (request as CallableRequest).data?.distanceMiles;
    const distanceMiles: number | null = (() => {
        if (typeof rawDistance !== "number") return null;
        if (!isFinite(rawDistance) || rawDistance < 0 || rawDistance > 500) {
            logger.warn("resolveChurchSmartAction: distanceMiles out of range — ignoring", { rawDistance });
            return null;
        }
        return rawDistance;
    })();

    logger.info("resolveChurchSmartAction: called", { uid, churchId, distanceMiles });

    const churchSnapshot = await loadChurchSnapshot(churchId);
    const churchData = churchSnapshot.data() ?? {};
    const liveStateSnapshot = await churchSnapshot.ref.collection("live_state").doc("current").get();
    const fitSnapshot = await db.collection("users").doc(uid).collection("church_fit").doc(churchId).get();

    const resolution = resolvePrimaryAction({
        liveState: normalizedString(liveStateSnapshot.data()?.state) as LiveStateValue,
        livestreamUrl: normalizedString(liveStateSnapshot.data()?.livestreamUrl || churchData.livestreamUrl) || null,
        fitScore: Number(fitSnapshot.data()?.score ?? 0),
        distanceMiles,
    });

    const writePayload = {
        primaryAction: resolution.primaryAction,
        secondaryActions: resolution.secondaryActions,
        reason: resolution.reason,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
        await db.collection("users").doc(uid).collection("church_smart_actions").doc(churchId).set(writePayload, { merge: true });
        logger.info("resolveChurchSmartAction: Firestore write succeeded", { uid, churchId, primaryAction: resolution.primaryAction });
    } catch (err) {
        logger.error("resolveChurchSmartAction: Firestore write failed", { uid, churchId, err });
        throw new HttpsError("internal", "Failed to update smart action.");
    }

    return {
        churchId,
        primaryAction: resolution.primaryAction,
        secondaryActions: resolution.secondaryActions,
        reason: resolution.reason,
        updatedAt: null,
    };
});

export const generateBereanChurchSuggestions = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request as CallableRequest);
    const uid = (request as CallableRequest).auth?.uid ?? null;
    logger.info("generateBereanChurchSuggestions: called", { uid: uid ?? "anonymous" });

    const stateSnapshot = uid
        ? await db.collection("users").doc(uid).collection("church_discovery_state").doc("main").get()
        : null;
    const stateData = stateSnapshot?.data() ?? {};
    const recentSearches = normalizedList(stateData.recentSearches);
    const preferredChips = normalizedList(stateData.preferredChips);

    if (!stateSnapshot?.exists) {
        logger.warn("generateBereanChurchSuggestions: no discovery state — returning generic suggestions", { uid });
    }

    const suggestions = [
        {
            id: "nearby",
            title: "Nearby churches",
            subtitle: "Based on your current discovery context.",
            iconName: "location.fill",
            intent: "nearby",
            confidence: 0.52,
        },
        {
            id: "saved",
            title: recentSearches.some((item) => item.toLowerCase().includes("prayer"))
                ? "Prayer-focused churches"
                : "Churches with deeper teaching near you",
            subtitle: recentSearches.length > 0
                ? "Shaped by recent searches and saved discovery context."
                : "Using currently available church profile data.",
            iconName: recentSearches.some((item) => item.toLowerCase().includes("prayer"))
                ? "hands.sparkles"
                : "book.closed",
            intent: recentSearches.some((item) => item.toLowerCase().includes("prayer"))
                ? "prayer"
                : "deeperTeaching",
            confidence: 0.4,
        },
        {
            id: "berean",
            title: preferredChips.includes("translation")
                ? "Accessible churches with translation support"
                : "Ask Berean for guidance",
            subtitle: preferredChips.includes("translation")
                ? "Only based on available accessibility and translation metadata."
                : "Use Berean when verified church context is limited.",
            iconName: preferredChips.includes("translation") ? "captions.bubble" : "sparkles",
            intent: preferredChips.includes("translation") ? "translation" : "askBerean",
            confidence: preferredChips.includes("translation") ? 0.43 : 0.31,
        },
    ];

    logger.info("generateBereanChurchSuggestions: returning suggestions", { uid: uid ?? "anonymous", count: suggestions.length });
    return {
        suggestions,
        fallback: "Suggestions are honest summaries of current church data only.",
    };
});
