import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();

type CandidateChurch = {
    churchId: string;
    name: string;
    denomination?: string;
    address?: string;
    distance?: number;
    serviceTime?: string;
    tags?: string[];
    categories?: string[];
    hasLivestream?: boolean;
    hasChildcare?: boolean;
    engagementScore?: number;
};

type UserContext = {
    preferredTags: string[];
    savedChurches: string[];
    visitedChurches: string[];
    recentSearches: string[];
    engagementSignals: Record<string, number>;
};

type ServiceStatus = {
    liveNow: boolean;
    startingSoon: boolean;
    nextServiceTime: string | null;
    urgencyLabel: string | null;
};

function requireAuth(request: { auth?: { uid?: string } }): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function normalizeList(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value.map((item) => String(item ?? "").trim()).filter(Boolean);
}

function normalizeText(value: unknown): string {
    return String(value ?? "").trim();
}

function toTitleCase(value: string): string {
    return value.replace(/\b\w/g, (match) => match.toUpperCase());
}

function mapNeedToTags(query: string): string[] {
    const lowered = query.toLowerCase();
    if (lowered.includes("lonely") || lowered.includes("community")) {
        return ["community", "small groups", "young adults"];
    }
    if (lowered.includes("new to faith") || lowered.includes("new believer")) {
        return ["new here", "new believer", "first timer"];
    }
    if (lowered.includes("deeper teaching") || lowered.includes("bible")) {
        return ["teaching", "bible", "expository"];
    }
    if (lowered.includes("prayer")) {
        return ["prayer", "charismatic", "worship"];
    }
    if (lowered.includes("kids") || lowered.includes("children")) {
        return ["family", "childcare", "kids"];
    }
    return [];
}

function readUserContext(data: FirebaseFirestore.DocumentData | undefined): UserContext {
    return {
        preferredTags: normalizeList(data?.preferredTags),
        savedChurches: normalizeList(data?.savedChurches),
        visitedChurches: normalizeList(data?.visitedChurches),
        recentSearches: normalizeList(data?.recentSearches),
        engagementSignals: typeof data?.engagementSignals === "object" && data?.engagementSignals
            ? data.engagementSignals as Record<string, number>
            : {},
    };
}

function flattenChurchTags(church: CandidateChurch, doc?: FirebaseFirestore.DocumentData): string[] {
    const raw = [
        ...normalizeList(church.tags),
        ...normalizeList(church.categories),
        ...normalizeList(doc?.tags),
        ...normalizeList(doc?.categories),
        ...normalizeList(doc?.personalityTags),
    ];
    return Array.from(new Set(raw.map((item) => item.toLowerCase())));
}

function coerceChurch(id: string, data: FirebaseFirestore.DocumentData): CandidateChurch {
    return {
        churchId: id,
        name: normalizeText(data.name),
        denomination: normalizeText(data.denomination),
        address: normalizeText(data.address),
        distance: typeof data.distance === "number" ? data.distance : undefined,
        serviceTime: normalizeText(data.serviceTime),
        tags: normalizeList(data.tags),
        categories: normalizeList(data.categories),
        hasLivestream: Boolean(data.hasLivestream),
        hasChildcare: Boolean(data.hasChildcare),
        engagementScore: typeof data.engagementScore === "number" ? data.engagementScore : 0,
    };
}

function parseServiceTimes(church: CandidateChurch, doc?: FirebaseFirestore.DocumentData): Array<{ label: string; day: number; hour: number; minute: number }> {
    const structured = Array.isArray(doc?.serviceTimes) ? doc?.serviceTimes as Array<Record<string, unknown>> : [];
    const parsed: Array<{ label: string; day: number; hour: number; minute: number }> = [];

    for (const item of structured) {
        const dayName = normalizeText(item.day ?? item.dayOfWeek);
        const timeName = normalizeText(item.time ?? item.startTime);
        const label = `${dayName} ${timeName}`.trim();
        const day = weekdayFor(dayName);
        const { hour, minute } = parseTime(timeName);
        if (day && hour !== null) {
            parsed.push({ label, day, hour, minute });
        }
    }

    if (parsed.length > 0) return parsed;

    const fallback = normalizeText(church.serviceTime);
    if (!fallback) return [];
    return fallback
        .split(/[,&]/g)
        .map((chunk) => chunk.trim())
        .filter(Boolean)
        .map((chunk) => {
            const parts = chunk.split(/\s+/);
            const day = weekdayFor(parts[0] ?? "Sunday") ?? 1;
            const time = parseTime(parts.slice(1).join(" "));
            return {
                label: chunk,
                day,
                hour: time.hour ?? 10,
                minute: time.minute,
            };
        });
}

function weekdayFor(value: string): number | null {
    switch (value.toLowerCase()) {
    case "sunday": return 1;
    case "monday": return 2;
    case "tuesday": return 3;
    case "wednesday": return 4;
    case "thursday": return 5;
    case "friday": return 6;
    case "saturday": return 7;
    default: return null;
    }
}

function parseTime(value: string): { hour: number | null; minute: number } {
    const match = value.match(/(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?/i);
    if (!match) return { hour: null, minute: 0 };
    let hour = Number(match[1]);
    const minute = Number(match[2] ?? "0");
    const meridiem = (match[3] ?? "").toUpperCase();
    if (meridiem === "PM" && hour < 12) hour += 12;
    if (meridiem === "AM" && hour === 12) hour = 0;
    return { hour, minute };
}

function computeServiceStatusFromChurch(
    church: CandidateChurch,
    doc: FirebaseFirestore.DocumentData | undefined,
    now = new Date()
): ServiceStatus {
    const times = parseServiceTimes(church, doc);
    if (times.length === 0) {
        return {
            liveNow: false,
            startingSoon: false,
            nextServiceTime: church.serviceTime || null,
            urgencyLabel: church.serviceTime || "No service times listed",
        };
    }

    let bestDate: Date | null = null;
    for (const time of times) {
        const candidate = new Date(now);
        candidate.setDate(now.getDate() + ((time.day - now.getDay() + 7) % 7));
        candidate.setHours(time.hour, time.minute, 0, 0);
        if (candidate < now) {
            candidate.setDate(candidate.getDate() + 7);
        }
        if (bestDate == null || candidate < bestDate) {
            bestDate = candidate;
        }
    }

    const sundayHour = now.getDay() === 0 ? now.getHours() : -1;
    const liveNow = sundayHour >= 9 && sundayHour < 12;
    const minutesUntil = bestDate ? Math.round((bestDate.getTime() - now.getTime()) / 60000) : Number.MAX_SAFE_INTEGER;
    const startingSoon = minutesUntil >= 0 && minutesUntil <= 60;

    let urgencyLabel: string | null = null;
    if (liveNow) urgencyLabel = "Live now";
    else if (startingSoon) urgencyLabel = `Starts in ${minutesUntil} min`;
    else urgencyLabel = times[0]?.label ?? church.serviceTime ?? null;

    return {
        liveNow,
        startingSoon,
        nextServiceTime: times[0]?.label ?? church.serviceTime ?? null,
        urgencyLabel,
    };
}

function derivePersonalityTags(church: CandidateChurch, doc?: FirebaseFirestore.DocumentData): string[] {
    const tags = new Set<string>();
    for (const tag of flattenChurchTags(church, doc)) {
        if (tag.includes("bible") || tag.includes("expository")) tags.add("Bible-heavy");
        if (tag.includes("worship")) tags.add("Worship-forward");
        if (tag.includes("family") || tag.includes("kids")) tags.add("Family-centered");
        if (tag.includes("traditional")) tags.add("Quiet/traditional");
        if (tag.includes("charismatic") || tag.includes("spirit")) tags.add("Charismatic");
        if (tag.includes("young")) tags.add("Young adult active");
        if (tag.includes("service") || tag.includes("outreach")) tags.add("Community-service focused");
        if (tag.includes("new") || tag.includes("welcome")) tags.add("New-believer friendly");
    }

    const denomination = normalizeText(church.denomination ?? doc?.denomination).toLowerCase();
    if (denomination.includes("baptist") || denomination.includes("presbyterian")) tags.add("Bible-heavy");
    if (denomination.includes("pentecostal")) tags.add("Charismatic");
    if (denomination.includes("catholic") || denomination.includes("methodist")) tags.add("Quiet/traditional");
    if (church.hasChildcare || doc?.hasChildcare === true) tags.add("Family-centered");

    return Array.from(tags);
}

function fitVerdict(value: number, strong: number, medium: number, close = false): string {
    if (close) {
        if (value <= strong) return "Close";
        if (value <= medium) return "Manageable";
        return "Far";
    }
    if (value >= strong) return "Strong";
    if (value >= medium) return "Medium";
    return "Developing";
}

async function loadLatestSermon(churchId: string): Promise<Record<string, unknown> | null> {
    const snapshot = await db.collection("churches").doc(churchId).collection("sermons")
        .orderBy("publishedAt", "desc")
        .limit(1)
        .get()
        .catch(() => null);
    if (!snapshot || snapshot.empty) return null;
    return snapshot.docs[0].data();
}

function buildSundayPlan(church: CandidateChurch, doc?: FirebaseFirestore.DocumentData): Record<string, string> {
    const driveMinutes = Math.max(8, Math.round((church.distance ?? 8) * 3.4));
    const reminderLead = driveMinutes + 15;
    return {
        serviceLabel: normalizeText(church.serviceTime) || "Service time available in church details",
        driveTimeLabel: `${driveMinutes} min drive`,
        reminderLabel: `Reminder ${reminderLead} min before`,
        parkingLabel: normalizeText(doc?.parkingInfo) || "Parking details in first-visit info",
        childcareLabel: doc?.hasChildcare === true ? "Children's check-in available" : "Childcare info not listed",
        whatToExpectLabel: normalizeText(doc?.dressCode) || "Come as you are",
        directionsLabel: normalizeText(church.address ?? doc?.address) || "Open directions in Maps",
    };
}

async function rankOneChurch(
    church: CandidateChurch,
    doc: FirebaseFirestore.DocumentData | undefined,
    userContext: UserContext,
    intent: string,
    query: string
): Promise<Record<string, unknown>> {
    const serviceStatus = computeServiceStatusFromChurch(church, doc);
    const tags = derivePersonalityTags(church, doc);
    const flattenedTags = flattenChurchTags(church, doc);
    const queryNeeds = mapNeedToTags(query);

    let score = 45;
    const reasons: string[] = [];

    if (typeof church.distance === "number") {
        const distanceBoost = Math.max(0, 24 - church.distance * 2.5);
        score += distanceBoost;
        if (church.distance <= 5) {
            reasons.push("Distance: close enough to attend consistently.");
        }
    }

    if (serviceStatus.liveNow) {
        score += 16;
        reasons.push("Service is live now.");
    } else if (serviceStatus.startingSoon) {
        score += 14;
        reasons.push("Service is starting soon.");
    }

    if (userContext.savedChurches.includes(church.churchId)) {
        score += 10;
        reasons.push("Already saved in your church journey.");
    }
    if (userContext.visitedChurches.includes(church.churchId)) {
        score += 8;
        reasons.push("You have visited before.");
    }

    const preferredTagMatches = userContext.preferredTags.filter((tag) => flattenedTags.includes(tag.toLowerCase()));
    if (preferredTagMatches.length > 0) {
        score += Math.min(16, preferredTagMatches.length * 6);
        reasons.push(`Matches your preferences for ${preferredTagMatches.slice(0, 2).join(" and ")}.`);
    }

    const intentKey = intent.toLowerCase();
    if (intentKey && flattenedTags.some((tag) => tag.includes(intentKey))) {
        score += 12;
        reasons.push(`Intent match for ${toTitleCase(intent)}.`);
    }

    if (queryNeeds.length > 0 && flattenedTags.some((tag) => queryNeeds.some((need) => tag.includes(need)))) {
        score += 14;
        reasons.push(`Aligned with your search for ${query}.`);
    }

    const firstTimerFriendly = doc?.welcomeTeamActive === true || flattenedTags.some((tag) => tag.includes("new") || tag.includes("welcome"));
    if (firstTimerFriendly) {
        score += 8;
        reasons.push("First-time friendly arrival support.");
    }

    score += Math.min(10, Number(church.engagementScore ?? 0));

    const sermon = await loadLatestSermon(church.churchId);
    const sermonTopic = normalizeText(sermon?.topic ?? sermon?.title);
    const sermonScripture = normalizeText(sermon?.scripture ?? sermon?.scriptureReference);
    const sermonStyle = normalizeText(sermon?.style);
    const sermonQuote = normalizeText(sermon?.quote ?? sermon?.keyQuote);
    const sermonMatchSummary = sermonTopic
        ? `Recent sermons focus on ${[sermonTopic, sermonScripture].filter(Boolean).join(", ")}.`
        : "";

    const topReason = reasons[0] ?? "Balanced fit across distance, service timing, and church profile.";
    const bestVisit = `Best first-time visit: ${serviceStatus.nextServiceTime ?? normalizeText(church.serviceTime) || "Sunday service"} - ${doc?.hasChildcare === true ? "childcare available" : "childcare details unclear"}, ${doc?.welcomeTeamActive === true ? "welcome team active" : "low-pressure arrival"}, ${normalizeText(doc?.crowdWindowHint) || "usually easier than the earliest service"}.`;

    const socialProof: string[] = [];
    if (typeof doc?.savedByNearbyCount === "number" && doc.savedByNearbyCount > 0) {
        socialProof.push(`${doc.savedByNearbyCount} people near you saved this church.`);
    }
    if (normalizeText(doc?.youngAdultAffinity)) {
        socialProof.push(`Popular with ${String(doc?.youngAdultAffinity).toLowerCase()}.`);
    }
    if (normalizeText(doc?.familyAreaSignal)) {
        socialProof.push(String(doc?.familyAreaSignal));
    }
    if (typeof doc?.amenFriendCount === "number" && doc.amenFriendCount > 0) {
        socialProof.push(`${doc.amenFriendCount} friends from AMEN follow this church.`);
    }

    return {
        churchId: church.churchId,
        score: Math.round(Math.min(99, score)),
        reason: topReason,
        reasonDetails: reasons.slice(0, 4),
        tags,
        nextService: serviceStatus.urgencyLabel,
        distance: church.distance ?? null,
        live: serviceStatus.liveNow,
        serviceSoon: serviceStatus.startingSoon,
        bestVisit,
        fitBreakdown: [
            { title: "Teaching", verdict: fitVerdict(flattenedTags.some((tag) => tag.includes("bible") || tag.includes("teaching")) ? 85 : 55, 80, 60) },
            { title: "Worship", verdict: fitVerdict(flattenedTags.some((tag) => tag.includes("worship")) ? 85 : 55, 80, 60) },
            { title: "Family fit", verdict: church.hasChildcare || doc?.hasChildcare === true ? "Strong" : "Medium" },
            { title: "Distance", verdict: fitVerdict(church.distance ?? 12, 5, 12, true) },
            { title: "First-time friendly", verdict: firstTimerFriendly ? "High" : "Medium" },
        ],
        socialProof,
        sermon: sermonTopic ? {
            topic: sermonTopic,
            scripture: sermonScripture || null,
            style: sermonStyle || null,
            quote: sermonQuote || null,
            matchSummary: sermonMatchSummary || null,
        } : null,
        firstVisit: {
            entrance: normalizeText(doc?.entranceInfo) || null,
            parking: normalizeText(doc?.parkingInfo) || null,
            whatToWear: normalizeText(doc?.dressCode) || null,
            childcareSummary: doc?.hasChildcare === true ? "Children's check-in available." : null,
            serviceLength: typeof doc?.serviceLengthMinutes === "number" ? `${doc.serviceLengthMinutes}-minute service` : null,
            greetingSummary: doc?.welcomeTeamActive === true ? "Welcome team usually available near the entrance." : null,
            livestreamPreview: normalizeText(doc?.livestreamURL) || null,
        },
        sundayPlan: buildSundayPlan(church, doc),
    };
}

export const computeServiceStatus = onCall(async (request) => {
    requireAuth(request);
    const churchId = normalizeText(request.data?.churchId);
    const explicitTimes = Array.isArray(request.data?.serviceTimes) ? request.data?.serviceTimes as unknown[] : [];

    let church: CandidateChurch = {
        churchId,
        name: "",
        serviceTime: normalizeText(request.data?.serviceTime),
    };
    let doc: FirebaseFirestore.DocumentData | undefined;

    if (churchId) {
        const snapshot = await db.collection("churches").doc(churchId).get().catch(() => null);
        if (snapshot?.exists) {
            doc = snapshot.data();
            church = { ...church, ...coerceChurch(churchId, doc ?? {}) };
        }
    }

    if (explicitTimes.length > 0) {
        doc = { ...(doc ?? {}), serviceTimes: explicitTimes };
    }

    return computeServiceStatusFromChurch(church, doc);
});

export const rankChurchesForUser = onCall(async (request) => {
    const uid = requireAuth(request);
    const intent = normalizeText(request.data?.intent);
    const query = normalizeText(request.data?.query);
    const provided = Array.isArray(request.data?.candidateChurches) ? request.data.candidateChurches as CandidateChurch[] : [];

    const userContextSnap = await db.collection("user_context").doc(uid).get().catch(() => null);
    const userContext = readUserContext(userContextSnap?.data());

    let churches = provided.filter((church) => normalizeText(church.churchId));
    if (churches.length === 0) {
        const snapshot = await db.collection("churches").limit(24).get();
        churches = snapshot.docs.map((doc) => coerceChurch(doc.id, doc.data()));
    }

    const docs = await Promise.all(churches.map(async (church) => {
        const snapshot = await db.collection("churches").doc(church.churchId).get().catch(() => null);
        return snapshot?.data();
    }));

    const results = await Promise.all(churches.map((church, index) => rankOneChurch(church, docs[index], userContext, intent, query)));
    results.sort((lhs, rhs) => Number(rhs.score) - Number(lhs.score));

    return { results };
});

export const generateChurchMatchesFromAnswers = onCall(async (request) => {
    const uid = requireAuth(request);
    const answers = request.data?.answers as Record<string, string | string[] | undefined> | undefined;
    if (!answers) {
        throw new HttpsError("invalid-argument", "answers are required.");
    }

    const mattersMost = normalizeList(answers.mattersMost ?? answers.priority);
    const timing = normalizeText(answers.when ?? answers.timing);
    const who = normalizeText(answers.who ?? answers.guests);
    const synthesizedQuery = [mattersMost.join(" "), timing, who].filter(Boolean).join(" ");

    const userContextSnap = await db.collection("user_context").doc(uid).get().catch(() => null);
    const userContext = readUserContext(userContextSnap?.data());
    userContext.preferredTags = Array.from(new Set([...userContext.preferredTags, ...mattersMost]));

    const churchSnap = await db.collection("churches").limit(24).get();
    const churches = churchSnap.docs.map((doc) => coerceChurch(doc.id, doc.data()));
    const ranked = await Promise.all(churches.map((church) => rankOneChurch(church, churchSnap.docs.find((doc) => doc.id === church.churchId)?.data(), userContext, mattersMost[0] ?? timing, synthesizedQuery)));

    ranked.sort((lhs, rhs) => Number(rhs.score) - Number(lhs.score));
    return { results: ranked.slice(0, 12) };
});

export const trackChurchInteraction = onCall(async (request) => {
    const uid = requireAuth(request);
    const churchId = normalizeText(request.data?.churchId);
    const action = normalizeText(request.data?.action);
    const metadata = typeof request.data?.metadata === "object" && request.data?.metadata ? request.data.metadata as Record<string, unknown> : {};

    if (!churchId || !action) {
        throw new HttpsError("invalid-argument", "churchId and action are required.");
    }

    const now = admin.firestore.Timestamp.now();
    const interactionRef = db.collection("users").doc(uid).collection("churchInteractions").doc(churchId);
    const userContextRef = db.collection("user_context").doc(uid);

    await db.runTransaction(async (transaction) => {
        const contextSnap = await transaction.get(userContextRef);
        const context = readUserContext(contextSnap.data());
        const recentSearches = normalizeList(context.recentSearches).slice(0, 9);

        const nextContext: FirebaseFirestore.UpdateData = {
            engagementSignals: {
                ...(context.engagementSignals ?? {}),
                [action]: ((context.engagementSignals ?? {})[action] ?? 0) + 1,
            },
            updatedAt: now,
        };

        if (action === "save" && !context.savedChurches.includes(churchId)) {
            nextContext.savedChurches = [...context.savedChurches, churchId];
        }
        if ((action === "visit" || action === "planned_visit") && !context.visitedChurches.includes(churchId)) {
            nextContext.visitedChurches = [...context.visitedChurches, churchId];
        }
        if (action === "search" && normalizeText(metadata.query)) {
            nextContext.recentSearches = [normalizeText(metadata.query), ...recentSearches.filter((item) => item !== metadata.query)].slice(0, 10);
        }

        transaction.set(interactionRef, {
            churchId,
            action,
            metadata,
            updatedAt: now,
            lastActionAt: now,
        }, { merge: true });
        transaction.set(userContextRef, nextContext, { merge: true });
    });

    return { success: true };
});
