import * as admin from "firebase-admin";

export type DiscoverItemType =
  | "church"
  | "testimony"
  | "prayerSafePost"
  | "sermonClip"
  | "scriptureReflection"
  | "creator"
  | "localCommunity"
  | "selahMedia"
  | "churchNotesMoment";

export type DiscoverSafetyCategory =
  | "prayer_safe"
  | "testimony_safe"
  | "church_safe"
  | "sermon_safe"
  | "youth_safe"
  | "sensitive_allowed"
  | "restricted_from_discover"
  | "blocked";

export type DiscoverItemDoc = {
  id: string;
  type: DiscoverItemType;
  title: string;
  subtitle?: string;
  caption?: string;
  sourceId: string;
  sourceType: string;
  media?: { thumbnailURL?: string; mediaURL?: string; durationSeconds?: number };
  author?: { id: string; name: string; avatarURL?: string };
  church?: { id: string; name: string; avatarURL?: string };
  topics?: string[];
  scriptureRefs?: string[];
  badges?: string[];
  createdAt?: admin.firestore.Timestamp;
  discoverVisibility?: "public" | "hidden";
};

export type DiscoverMetadata = {
  qualityScore: number;
  safetyScore: number;
  originalityScore: number;
  spiritualUsefulnessScore: number;
  creatorTrustScore: number;
  localFitScore?: number;
  freshnessScore?: number;
  intentMatchScore?: number;
  moderationStatus: "approved" | "pending" | "rejected";
  recommendationEligible: boolean;
  sensationalismPenalty?: number;
  repetitionPenalty?: number;
  unresolvedModerationPenalty?: number;
  lowTrustAIPenalty?: number;
  safetyCategory?: DiscoverSafetyCategory;
  aiAssisted?: boolean;
  scriptureRefsApproved?: boolean;
  bereanReviewed?: boolean;
};
