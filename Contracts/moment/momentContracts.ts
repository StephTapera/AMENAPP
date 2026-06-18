export type MomentType =
    | "prayer"
    | "scripture"
    | "sermon"
    | "event"
    | "creator"
    | "study"
    | "mission"
    | "thread";

export type TemporalState = "upcoming" | "live" | "recap" | "evergreen";

export type VerbFamily = "gather" | "deepen" | "invite" | "follow";

export interface Moment {
    id: string;
    type: MomentType;
    temporalState: TemporalState;
    refId: string;
    ownerId: string;
    createdAt: number;
}

export interface Flags {
    moment_system_enabled: boolean;
    deepen_actions_enabled: boolean;
    gather_live_enabled: boolean;
    gather_compliance_gate_cleared: boolean;
}

export const defaultMomentFlags: Flags = {
    moment_system_enabled: false,
    deepen_actions_enabled: false,
    gather_live_enabled: false,
    gather_compliance_gate_cleared: false,
};

export type DeepenActionKind =
    | "summarize"
    | "crossReference"
    | "generatePrayer"
    | "generateStudyGuide"
    | "generateDiscussion"
    | "generateDevotional"
    | "saveTo";

export type GatherActionKind = "prayLive" | "joinAudio" | "joinDiscussion";

export type InviteActionKind = "invite";

export type FollowActionKind = "follow";

export type ActionKind =
    | DeepenActionKind
    | GatherActionKind
    | InviteActionKind
    | FollowActionKind;

export type ActionReason =
    | "complianceGateRequired"
    | "flagDisabled"
    | "uiDeferred"
    | "v1StubOnly";

export interface Action {
    id: ActionKind;
    family: VerbFamily;
    enabled: boolean;
    reason?: ActionReason;
}

export const v1DeepenEnabledMomentTypes: readonly MomentType[] = [
    "prayer",
    "scripture",
    "sermon",
    "event",
    "creator",
    "study",
    "mission",
    "thread",
];

export const v1GatherEligibleMomentTypes: readonly MomentType[] = [
    "prayer",
    "scripture",
    "sermon",
    "event",
    "creator",
    "study",
    "mission",
    "thread",
];

const deepenActions: readonly Action[] = [
    { id: "summarize", family: "deepen", enabled: true },
    { id: "crossReference", family: "deepen", enabled: true },
    { id: "generatePrayer", family: "deepen", enabled: true },
    { id: "generateStudyGuide", family: "deepen", enabled: true },
    { id: "generateDiscussion", family: "deepen", enabled: true },
    { id: "generateDevotional", family: "deepen", enabled: true },
    { id: "saveTo", family: "deepen", enabled: true },
];

const gatherActionKinds: readonly GatherActionKind[] = [
    "prayLive",
    "joinAudio",
    "joinDiscussion",
];

export function availableActions(moment: Moment, flags: Flags): Action[] {
    if (!flags.moment_system_enabled) {
        return [];
    }

    const actions: Action[] = [];

    if (flags.deepen_actions_enabled && v1DeepenEnabledMomentTypes.includes(moment.type)) {
        actions.push(...deepenActions);
    }

    const canSurfaceGather =
        moment.temporalState === "live" &&
        flags.gather_live_enabled &&
        v1GatherEligibleMomentTypes.includes(moment.type);

    if (canSurfaceGather) {
        actions.push(...gatherActionKinds.map((id): Action => ({
            id,
            family: "gather",
            enabled: flags.gather_compliance_gate_cleared,
            reason: flags.gather_compliance_gate_cleared ? undefined : "complianceGateRequired",
        })));
    }

    actions.push(
        { id: "invite", family: "invite", enabled: false, reason: "uiDeferred" },
        { id: "follow", family: "follow", enabled: false, reason: "uiDeferred" },
    );

    return actions;
}

export type BereanMode = "ask" | "discern" | "build";

export type SaveTarget =
    | "prayerJournal"
    | "studyJournal"
    | "churchNotes"
    | "sermonCollection"
    | "savedTeachings";

export interface DeepenRequest {
    moment: Moment;
    action: DeepenActionKind;
    requesterId: string;
    bereanMode: BereanMode;
    saveTarget?: SaveTarget;
    locale?: string;
}

export interface GuardianReview {
    passed: boolean;
    policyVersion: string;
    reason?: string;
}

export interface DeepenResult {
    momentId: string;
    action: DeepenActionKind;
    output: string;
    citations: string[];
    savedTo?: SaveTarget;
    guardian: GuardianReview;
    createdAt: number;
}

export interface GatherRequest {
    moment: Moment;
    action: GatherActionKind;
    requesterId: string;
}

export interface GatherResult {
    momentId: string;
    action: GatherActionKind;
    status: "gated" | "notImplemented";
    reason: "complianceGateRequired" | "flagDisabled" | "v1StubOnly";
}

export interface InviteRequest {
    moment: Moment;
    requesterId: string;
    recipientIds: string[];
}

export interface FollowRequest {
    moment: Moment;
    requesterId: string;
}

export const momentFunctionRegion = "us-east1";

export const deepenFunctionNames = [
    "momentSummarize",
    "momentCrossReference",
    "momentGeneratePrayer",
    "momentGenerateStudyGuide",
    "momentGenerateDiscussion",
    "momentGenerateDevotional",
    "momentSaveTo",
] as const;

export const gatherFunctionNames = [
    "momentPrayLive",
    "momentJoinAudio",
    "momentJoinDiscussion",
] as const;

export interface MomentFirestoreDocument extends Moment {
    schemaVersion: 1;
    updatedAt: number;
}

export interface MomentSaveDocument {
    schemaVersion: 1;
    momentId: string;
    ownerId: string;
    target: SaveTarget;
    deepenAction: DeepenActionKind;
    content: string;
    citations: string[];
    guardian: GuardianReview;
    createdAt: number;
}
