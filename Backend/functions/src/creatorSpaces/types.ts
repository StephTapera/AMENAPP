export type CreatorMediaAssetType = "presence" | "single" | "video" | "audio" | "creation";
export type CreatorFrameLayout = "pip" | "split" | "stacked";
export type CreatorFeedDistribution = "daily_portion" | "profile_only" | "rooms_only";
export type CreatorModerationStatus = "pending" | "approved" | "blocked";

export interface CreatorFrameDraft {
    storagePath: string;
    width: number;
    height: number;
}

export interface CreatorAudioDraft {
    storagePath: string;
    spatial: boolean;
}

export interface CreatorMediaFramesDraft {
    back?: CreatorFrameDraft;
    front?: CreatorFrameDraft;
    composite?: CreatorFrameDraft;
    audio?: CreatorAudioDraft;
    layout: CreatorFrameLayout;
}

export interface CreatorMediaAssetDraft {
    type: CreatorMediaAssetType;
    frames: CreatorMediaFramesDraft;
    context?: {
        location?: string;
        emotionTags?: string[];
        ambientSignals?: Record<string, string>;
    };
    feed?: {
        distribution?: CreatorFeedDistribution;
    };
    provenance?: {
        capturedOnDevice?: boolean;
        sourceCamera?: string;
        editedWithAI?: boolean;
    };
}

export type CreatorSpacePaidListingKind = "subscription" | "event_pass" | "class" | "study" | "media_pack";

export interface CreatorSpacePaidListingInput {
    spaceId: string;
    title: string;
    description?: string;
    kind: CreatorSpacePaidListingKind;
    stripePriceId: string;
    visibility?: "private" | "members" | "public";
}
