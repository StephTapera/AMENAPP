export type ContentType =
  | "post"
  | "video"
  | "note"
  | "design"
  | "selah"
  | "churchNote"
  | "discussion"
  | "aiSession"
  | "communityPost";

export type ContentVisibility =
  | "public"
  | "followers"
  | "group"
  | "private"
  | "circle"
  | "community"
  | "church"
  | "draft";

export interface ContentBlock {
  id: string;
  type:
    | "text"
    | "heading"
    | "checklist"
    | "quote"
    | "image"
    | "video"
    | "audio"
    | "scripture"
    | "link"
    | "aiSummary"
    | "discussion"
    | "divider"
    | "callout";
  text?: string;
  mediaRefId?: string;
  order: number;
  metadata?: Record<string, string>;
}

export interface MediaRef {
  id: string;
  mediaId?: string;
  type: "image" | "video" | "audio" | "unknown";
  url?: string;
  thumbnailURL?: string;
  storagePath?: string;
  width?: number;
  height?: number;
  duration?: number;
  caption?: string;
  altText?: string;
  processingState?: "queued" | "uploading" | "processing" | "ready" | "failed";
}

export interface ContentNode {
  id: string;
  ownerId: string;
  author: {
    displayName: string;
    username?: string;
    avatarURL?: string;
  };
  type: ContentType;
  visibility: ContentVisibility;
  title?: string;
  text?: string;
  blocks: ContentBlock[];
  mediaRefs: MediaRef[];
  collaborators: string[];
  moderationState: {
    status: "pending" | "approved" | "limited" | "rejected" | "removed" | "appealed" | "escalated";
    reason?: string;
    reviewedAt?: FirebaseFirestore.Timestamp;
    reviewedBy?: string;
  };
  aiMetadata: {
    usedAI: boolean;
    provider?: string;
    model?: string;
    disclosureLabel?: string;
    promptSummary?: string;
    generatedAt?: FirebaseFirestore.Timestamp;
    userAccepted?: boolean;
  };
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  deletedAt?: FirebaseFirestore.Timestamp;
  sourceReferences?: Array<Record<string, unknown>>;
  parentContentId?: string;
  remixSourceId?: string;
  saveEligible: boolean;
  shareEligible: boolean;
  accessibility?: Record<string, unknown>;
  language?: Record<string, unknown>;
  translation?: Record<string, unknown>;
  publishState: "draft" | "published" | "archived";
}

export const validContentTypes: ContentType[] = [
  "post",
  "video",
  "note",
  "design",
  "selah",
  "churchNote",
  "discussion",
  "aiSession",
  "communityPost",
];

export const validContentVisibilities: ContentVisibility[] = [
  "public",
  "followers",
  "group",
  "private",
  "circle",
  "community",
  "church",
  "draft",
];
