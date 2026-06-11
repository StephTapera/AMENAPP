import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type {
    AmbientBereanSuggestion,
    AmbientContext,
    AmbientMode,
    BroadcastRef,
    EventRef,
    NoteRef,
    PrayerRef,
    ThreadRef,
} from "./types";
import { enforceAmbientContextRateLimit, requireAmbientOSEnabled } from "./guards";

const validModes = new Set<AmbientMode>(["default", "driving", "atChurch"]);

export const getAmbientContext = onCall(
    { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 15 },
    async (req): Promise<AmbientContext> => {
        if (!req.auth) {
            throw new HttpsError("unauthenticated", "Sign in required.");
        }

        const uid = req.auth.uid;
        await requireAmbientOSEnabled();
        await enforceAmbientContextRateLimit(uid);

        const requestedMode = req.data?.mode as AmbientMode | undefined;
        const mode: AmbientMode = requestedMode && validModes.has(requestedMode) ? requestedMode : "default";
        const db = getFirestore();
        const userRef = db.collection("users").doc(uid);
        const now = new Date();
        const startOfToday = new Date(now);
        startOfToday.setHours(0, 0, 0, 0);
        const startOfTomorrow = new Date(startOfToday);
        startOfTomorrow.setDate(startOfTomorrow.getDate() + 1);

        const [
            userSnap,
            prayerSnap,
            notesSnap,
            threadsSnap,
            calendarSnap,
            selahSnap,
            ariseSnap,
        ] = await Promise.all([
            userRef.get(),
            userRef.collection("prayers")
                .where("status", "in", ["open", "awaitingResponse"])
                .orderBy("createdAt", "desc")
                .limit(5)
                .get(),
            userRef.collection("churchNotes")
                .where("status", "==", "draft")
                .orderBy("editedAt", "desc")
                .limit(3)
                .get(),
            db.collection("messages")
                .where("participants", "array-contains", uid)
                .where("needsFollowUp", "==", true)
                .orderBy("lastMessageAt", "desc")
                .limit(5)
                .get(),
            userRef.collection("calendarEvents")
                .where("startsAt", ">=", Timestamp.fromDate(startOfToday))
                .where("startsAt", "<", Timestamp.fromDate(startOfTomorrow))
                .orderBy("startsAt")
                .limit(10)
                .get(),
            userRef.collection("selahProgress").doc("current").get(),
            db.collection("ariseBroadcasts")
                .where("scheduledAt", ">=", Timestamp.fromDate(now))
                .orderBy("scheduledAt")
                .limit(3)
                .get(),
        ]);

        const userData = userSnap.data() ?? {};
        const firstName = stringValue(userData.firstName, "Friend");
        const tz = stringValue(userData.timezone ?? userData.tz, "America/New_York");
        const localTime = now.toISOString();

        const awaitingResponse: PrayerRef[] = prayerSnap.docs.map((doc) => ({
            id: doc.id,
            title: stringValue(doc.data().title, "Prayer Request"),
            deepLink: `amen://prayer/${doc.id}`,
            createdAt: isoValue(doc.data().createdAt),
        }));

        const unfinished: NoteRef[] = notesSnap.docs.map((doc) => ({
            id: doc.id,
            title: stringValue(doc.data().title, "Untitled Note"),
            deepLink: `amen://notes/${doc.id}`,
            editedAt: isoValue(doc.data().editedAt),
        }));

        const needingFollowUp: ThreadRef[] = threadsSnap.docs.map((doc) => ({
            id: doc.id,
            title: stringValue(doc.data().title, "Conversation"),
            deepLink: `amen://messages/${doc.id}`,
            lastMessageAt: isoValue(doc.data().lastMessageAt),
        }));

        const unreadSnap = await db.collection("messages")
            .where("participants", "array-contains", uid)
            .where("unreadBy", "array-contains", uid)
            .count()
            .get();

        const todayEvents: EventRef[] = calendarSnap.docs.map((doc) => ({
            id: doc.id,
            title: stringValue(doc.data().title, "Event"),
            deepLink: `amen://calendar/${doc.id}`,
            startsAt: isoValue(doc.data().startsAt),
            endsAt: optionalIsoValue(doc.data().endsAt),
        }));

        const churchId = stringValue(userData.primaryChurchId, "");
        const { upcomingEvents, nextService } = await loadChurchEvents(churchId);
        const selahData = selahSnap.data() ?? {};
        const selahBook = typeof selahData.book === "string" ? selahData.book : undefined;
        const selahChapter = typeof selahData.chapter === "number" ? selahData.chapter : 1;

        const upcomingBroadcasts: BroadcastRef[] = ariseSnap.docs.map((doc) => ({
            id: doc.id,
            title: stringValue(doc.data().title, "Broadcast"),
            deepLink: `amen://arise/${doc.id}`,
            scheduledAt: isoValue(doc.data().scheduledAt),
        }));

        const bereanSuggestion: AmbientBereanSuggestion | undefined = makeBereanSuggestion(
            awaitingResponse.length,
            Number(selahData.streakDays ?? 0),
        );

        return {
            generatedAt: now.toISOString(),
            user: { id: uid, firstName, localTime, tz },
            prayer: { awaitingResponse, openRequests: awaitingResponse.length },
            notes: { unfinished, lastEditedAt: unfinished[0]?.editedAt },
            messages: { needingFollowUp, unreadThreads: unreadSnap.data().count },
            calendar: { today: todayEvents, nextEvent: todayEvents[0] },
            church: { upcomingEvents, nextService },
            selah: {
                streakDays: Number(selahData.streakDays ?? 0),
                resumeAt: selahBook ? {
                    book: selahBook,
                    chapter: selahChapter,
                    deepLink: `amen://selah/${encodeURIComponent(selahBook)}/${selahChapter}`,
                } : undefined,
            },
            arise: { upcomingBroadcasts },
            bereanSuggestion,
            mode,
        };
    },
);

async function loadChurchEvents(churchId: string): Promise<{ upcomingEvents: EventRef[]; nextService?: EventRef }> {
    if (!churchId) {
        return { upcomingEvents: [] };
    }

    const snap = await getFirestore().collection("churches").doc(churchId)
        .collection("events")
        .where("startsAt", ">=", Timestamp.now())
        .orderBy("startsAt")
        .limit(3)
        .get();

    const upcomingEvents: EventRef[] = snap.docs.map((doc) => ({
        id: doc.id,
        title: stringValue(doc.data().title, "Service"),
        deepLink: `amen://church/${churchId}/event/${doc.id}`,
        startsAt: isoValue(doc.data().startsAt),
        endsAt: optionalIsoValue(doc.data().endsAt),
    }));

    return {
        upcomingEvents,
        nextService: upcomingEvents.find((event) => event.title.toLowerCase().includes("service")) ?? upcomingEvents[0],
    };
}

function makeBereanSuggestion(prayerCount: number, streakDays: number): AmbientBereanSuggestion | undefined {
    if (streakDays === 0) {
        return { kind: "study", label: "Start your Selah reading today", deepLink: "amen://selah" };
    }

    if (prayerCount > 0) {
        return {
            kind: "pray",
            label: prayerCount === 1 ? "One prayer request is awaiting your attention" : "Prayer requests are awaiting your attention",
            deepLink: "amen://prayer",
        };
    }

    return undefined;
}

function stringValue(value: unknown, fallback: string): string {
    return typeof value === "string" && value.trim().length > 0 ? value : fallback;
}

function isoValue(value: unknown): string {
    return optionalIsoValue(value) ?? new Date().toISOString();
}

function optionalIsoValue(value: unknown): string | undefined {
    if (value instanceof Timestamp) {
        return value.toDate().toISOString();
    }

    if (typeof value === "object" && value && "toDate" in value && typeof value.toDate === "function") {
        return value.toDate().toISOString();
    }

    if (typeof value === "string") {
        return value;
    }

    return undefined;
}
