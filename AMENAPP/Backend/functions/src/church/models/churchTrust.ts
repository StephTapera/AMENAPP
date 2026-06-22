export type ConfidenceLevel = "low" | "medium" | "high" | "verified";

export type ChurchVerificationStatus = "unverified" | "pending" | "verified" | "rejected";
export type ChurchVerificationLevel = "basic" | "official" | "trusted";
export type ChurchModerationState = "approved" | "rejected" | "needsReview" | "blocked";
export type ChurchAdminRole = "owner" | "admin" | "editor" | "moderator";
export type ChurchLivestreamProvider = "youtube" | "vimeo" | "direct_rtmp" | "direct_hls" | "embedded" | "unknown";

export type GroundingSource = {
    id: string;
    type:
        | "verifiedMetadata"
        | "officialWebsite"
        | "approvedMedia"
        | "livestream"
        | "serviceSchedule"
        | "adminProvided"
        | "userPreference"
        | "publicMetadata";
    title: string;
    detail?: string | null;
    url?: string | null;
    verified: boolean;
    updatedAt?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue | null;
};

export type ConfidenceEnvelope = {
    confidence: number;
    confidenceLevel: ConfidenceLevel;
    sources: GroundingSource[];
    updatedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
    note?: string | null;
};

export type ChurchVerificationRecord = {
    verificationStatus: ChurchVerificationStatus;
    verificationLevel: ChurchVerificationLevel;
    verifiedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp | null;
    verifiedBy: string | null;
    officialWebsiteVerified: boolean;
    livestreamVerified: boolean;
    ownershipClaimed: boolean;
    profileConfidence: number;
    moderationStatus: ChurchModerationState;
};

export type ChurchAdminRecord = {
    churchIds: string[];
    role: ChurchAdminRole;
    permissions: string[];
    createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
};

export type ModerationQueueRecord = {
    type: string;
    source: string;
    churchId: string;
    uploadedBy?: string | null;
    moderationState: ChurchModerationState;
    moderationReasons: string[];
    aiScores: Record<string, number>;
    escalated: boolean;
    reviewedBy?: string | null;
    reviewedAt?: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp | null;
    createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
    history?: Array<Record<string, unknown>>;
};

export type LivestreamRecord = {
    provider: ChurchLivestreamProvider;
    title: string;
    thumbnailUrl?: string | null;
    streamUrl: string;
    liveNow: boolean;
    startedAt?: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp | null;
    scheduledAt?: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp | null;
    viewerSignal?: number | null;
    ingestConfidence: number;
    updatedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
    sources: GroundingSource[];
};
