export type MediaCaptionModerationStatus =
  | "not_required"
  | "pending"
  | "approved"
  | "rejected"
  | "removed";

export interface MediaCaptionModeration {
  status: MediaCaptionModerationStatus;
  reason?: string | null;
  checkedAt?: FirebaseFirestore.Timestamp | null;
}

export interface PublishMediaItemInput {
  id?: string;
  mediaId?: string;
  mediaIndex: number;
  type: "image" | "video";
  url: string;
  storagePath?: string | null;
  caption?: string | null;
  altText?: string | null;
  scriptureRefs?: string[];
  reflectionPrompt?: string | null;
  captionModeration?: never;
}

export type MediaCaptionErrorCode =
  | "media-caption-too-long"
  | "media-caption-rejected"
  | "validation-failed"
  | "network"
  | "rate-limited";

export const MEDIA_CAPTION_LIMITS = {
  caption: 2200,
  altText: 1000,
  scriptureRefs: 10,
  reflectionPrompt: 500,
} as const;
