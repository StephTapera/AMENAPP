// types.ts — Shared types for Hey Feed Cloud Functions

export type HeyFeedNLAction = "increase" | "decrease" | "mute" | "explore" | "balance";

export type HeyFeedDurationType =
  | "session"
  | "today"
  | "three_days"
  | "seven_days"
  | "persistent";

export type HeyFeedTargetType =
  | "topic"
  | "tone"
  | "format"
  | "creator_type"
  | "relationship"
  | "locality"
  | "format"
  | "novelty"
  | "intensity";

export interface HeyFeedNLTarget {
  id: string;
  type: HeyFeedTargetType;
  label: string;
  confidence: number;
}

export interface HeyFeedParsedIntent {
  action: HeyFeedNLAction;
  targets: HeyFeedNLTarget[];
  duration: HeyFeedDurationType;
  strength: number;          // 0.0–1.0
  confidence: number;        // 0.0–1.0
  originalText: string;
  requiresConfirmation: boolean;
  parserVersion: number;
}

export interface FeedNLPreference {
  id: string;
  userId: string;
  action: HeyFeedNLAction;
  targetId: string;
  targetLabel: string;
  targetType: HeyFeedTargetType;
  strength: number;
  duration: HeyFeedDurationType;
  source: string;
  isActive: boolean;
  isPaused: boolean;
  createdAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp | null;
}

export interface FeedNLPreferenceUpdate {
  isActive?: boolean;
  isPaused?: boolean;
  strength?: number;
  duration?: HeyFeedDurationType;
  expiresAt?: FirebaseFirestore.Timestamp | null;
}
