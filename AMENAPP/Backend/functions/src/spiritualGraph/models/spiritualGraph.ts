export type SpiritualGraphNodeType =
    | "user"
    | "church"
    | "ministry"
    | "event"
    | "studyInterest"
    | "worshipStyle"
    | "servicePattern"
    | "volunteerActivity"
    | "savedContent"
    | "prayerInterest";

export type SpiritualGraphEdgeType =
    | "attends"
    | "saved"
    | "visited"
    | "interested"
    | "studies"
    | "volunteers"
    | "watches"
    | "participates"
    | "serves"
    | "connectedTo";

export type SpiritualMemoryType =
    | "churchVisit"
    | "savedSermon"
    | "studyTopic"
    | "prayerHabit"
    | "volunteerInterest"
    | "serviceAttendance"
    | "recurringMinistry"
    | "spiritualGoal"
    | "savedScriptureTheme";

export type SpiritualGraphEdgeRecord = {
    fromId: string;
    toId: string;
    type: SpiritualGraphEdgeType;
    strength: number;
    confidence: number;
    createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
    updatedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
};

export type SpiritualMemoryRecord = {
    type: SpiritualMemoryType;
    source: string;
    tags: string[];
    createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
    confidence: number;
    visibility: "privateOnly" | "userApprovedForBerean" | "exportOnly";
    derivedInsights: string[];
};
