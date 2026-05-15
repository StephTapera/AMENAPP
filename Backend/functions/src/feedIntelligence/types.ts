export type FeedDirectionIntentType =
  | "increaseTopic" | "decreaseTopic" | "emotionalRegulation" | "spiritualGrowth"
  | "worship" | "bibleStudy" | "localChurch" | "reduceConflict" | "reducePolitics"
  | "reduceOutrage" | "creatorAffinity" | "timeBasedPreference" | "sabbathRest"
  | "notificationPreference" | "safetyConcern" | "unknown";

export type FeedDirectionDuration = "session" | "now" | "today" | "week" | "always";
export type FeedDirectionIntensity = "light" | "medium" | "strong";
export type FeedDirectionVisibility = "privateOnly" | "applyAndPost";
export type FeedSurface = "home" | "media" | "suggestedCreators" | "notifications" | "church" | "search";
export type SignalStatus = "active" | "expired" | "revoked" | "rejected";
export type PostRecommendationAction = "more_like_this" | "less_like_this" | "hide_topic" | "hide_creator" | "reset_related";
export type FeedResetScope = "temporary" | "emotional" | "creator" | "topic" | "all";

export interface ComposerFeedDirectionContext {
  source: string;
  timezone: string;
  localHour: number;
  isSunday: boolean;
  reduceMotionEnabled: boolean;
  reduceTransparencyEnabled: boolean;
}

export interface SubmitFeedDirectionInput {
  rawText: string;
  composerContext: ComposerFeedDirectionContext;
  duration: FeedDirectionDuration;
  intensity: FeedDirectionIntensity;
  visibility: FeedDirectionVisibility;
  affectedSurfaces: FeedSurface[];
  clientDetectionConfidence: number;
}

export interface FeedSignalSafety {
  moderationStatus: "clean" | "flagged" | "rejected";
  safetyNotice?: string;
  echoChamberRisk: boolean;
  selfHarmRisk: boolean;
  manipulationRisk: boolean;
}

export interface FeedIntelligenceSignalDoc {
  signalId: string;
  uid: string;
  rawText: string;
  sanitizedText: string;
  interpretedSummary: string;
  intentType: FeedDirectionIntentType;
  confidence: number;
  topicsIncreased: string[];
  topicsDecreased: string[];
  modesActivated: string[];
  duration: FeedDirectionDuration;
  intensity: FeedDirectionIntensity;
  affectedSurfaces: FeedSurface[];
  visibility: FeedDirectionVisibility;
  source: "composer" | "post_card" | "settings" | "why_this_post";
  status: SignalStatus;
  safety: FeedSignalSafety;
  expiresAt: FirebaseFirestore.Timestamp | null;
  createdAt: FirebaseFirestore.FieldValue;
  updatedAt: FirebaseFirestore.FieldValue;
}

export interface FeedIntelligenceProfile {
  uid: string;
  version: number;
  updatedAt: FirebaseFirestore.FieldValue;
  activeModes: string[];
  boostedTopics: Record<string, number>;
  suppressedTopics: Record<string, number>;
  creatorAffinities: Record<string, number>;
  emotionalPreferences: Record<string, number>;
  spiritualPreferences: Record<string, number>;
  surfaceWeights: Record<string, Record<string, number>>;
  feedHealth: FeedHealthState;
  resetAvailable: boolean;
}

export interface FeedHealthState {
  reduceOutrage: boolean;
  reduceRapidCuts: boolean;
  preferCalmContent: boolean;
  preserveDiversity: boolean;
}

export interface ClassificationResult {
  intentType: FeedDirectionIntentType;
  confidence: number;
  topicsIncreased: string[];
  topicsDecreased: string[];
  modesActivated: string[];
  feedHealthUpdates: Partial<FeedHealthState>;
  interpretedSummary: string;
  safetyNotice?: string;
  echoChamberRisk: boolean;
}

export interface RankingDelta {
  surface: FeedSurface;
  topicBoosts: Record<string, number>;
  topicPenalties: Record<string, number>;
  modeAdjustments: Record<string, number>;
}
