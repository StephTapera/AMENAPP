export type SignalType =
    | "noteSaved"
    | "noteThemeDetected"
    | "churchSaved"
    | "churchUnsaved"
    | "churchViewed"
    | "visitVerified"
    | "prayerCreated"
    | "prayerAnswered"
    | "prayerReminderActed"
    | "giftCompleted"
    | "givingCauseViewed"
    | "messageSent"
    | "prayerExtractedFromMessage"
    | "studyStarted"
    | "studyCompleted"
    | "verseReflected"
    | "wellnessToolUsed"
    | "crisisSurfaceOpened"
    | "groupJoined"
    | "eventRSVPed"
    | "volunteerMatched"
    | "sessionRhythmTick";

export type TierCeiling = "s" | "c" | "p";

export type GraphNodeType =
    | "church"
    | "churchVisit"
    | "sermon"
    | "note"
    | "prayerRequest"
    | "person"
    | "group"
    | "community"
    | "gift"
    | "cause"
    | "event"
    | "study"
    | "verse"
    | "skill"
    | "interest"
    | "goal"
    | "milestone"
    | "wellnessActivity"
    | "reflection";

export type ConsentEdge =
    | "notesToMatching"
    | "notesToGiving"
    | "messagesToPrayer"
    | "locationToVisits"
    | "givingToFeed"
    | "activityToCheckIns"
    | "graphToBerean"
    | "graphToCohorts"
    | "activityToRhythm"
    | "crossDeviceContinuity";

export interface GraphRef {
    nodeType: GraphNodeType;
    nodeID: string;
}

export type AnyCodableValue =
    | string
    | number
    | boolean
    | null
    | AnyCodableValue[]
    | { [key: string]: AnyCodableValue };

export interface ContextSignal {
    id: string;
    type: SignalType;
    tierCeiling: TierCeiling;
    subjectRefs: GraphRef[];
    payload: { [key: string]: AnyCodableValue };
    occurredAt: string;
    decayHalfLifeDays: number;
    consentEdgeRequired?: ConsentEdge | null;
}

export const signalTypes: SignalType[] = [
    "noteSaved",
    "noteThemeDetected",
    "churchSaved",
    "churchUnsaved",
    "churchViewed",
    "visitVerified",
    "prayerCreated",
    "prayerAnswered",
    "prayerReminderActed",
    "giftCompleted",
    "givingCauseViewed",
    "messageSent",
    "prayerExtractedFromMessage",
    "studyStarted",
    "studyCompleted",
    "verseReflected",
    "wellnessToolUsed",
    "crisisSurfaceOpened",
    "groupJoined",
    "eventRSVPed",
    "volunteerMatched",
    "sessionRhythmTick"
];

export function assertServerEmittable(signal: ContextSignal): void {
    if (signal.tierCeiling === "s") {
        throw new Error("Tier-S context signals must never be ingested by server functions.");
    }
}
