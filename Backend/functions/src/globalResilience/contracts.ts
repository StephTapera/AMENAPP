/**
 * contracts.ts
 * AMEN — Global Resilience System
 * TypeScript interfaces mirroring GlobalResilienceContracts.swift.
 * All Firestore fields use snake_case. All TypeScript property names use camelCase.
 * Export all types so consumers can import what they need without wildcard imports.
 */

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

export type DeviceTier = "low" | "mid" | "high";

export type NetworkClass =
  | "offline"
  | "constrained"
  | "expensive"
  | "standard"
  | "fast";

export type DataMode = "automatic" | "lowData" | "wifiOnlyMedia" | "standard";

export type StorageTier = "critical" | "low" | "medium" | "ample";

export type OutboxStatus =
  | "draft"
  | "pending"
  | "sent"
  | "delivered"
  | "synced"
  | "failed";

export type VerificationTier =
  | "none"
  | "person"
  | "leader"
  | "churchLinked"
  | "ministry"
  | "charityDonation"
  | "eventHost";

export type DmRiskLevel = "low" | "medium" | "high" | "blocked";

export type BulletinSeverity = "info" | "warning" | "critical" | "emergency";

// ---------------------------------------------------------------------------
// DeviceCapabilityProfile
// ---------------------------------------------------------------------------

/**
 * Firestore path: devices/{uid}/capability_profiles/{deviceId}
 * snake_case fields on the wire; camelCase in TypeScript.
 */
export interface DeviceCapabilityProfile {
  /** Canonical platform string, e.g. "ios", "ipados", "visionos" */
  platform: string;
  device_model: string;
  device_tier: DeviceTier;
  network_class: NetworkClass;
  is_constrained_path: boolean;
  is_expensive_path: boolean;
  low_power_mode_enabled: boolean;
  /** String representation of thermal state: "nominal" | "fair" | "serious" | "critical" */
  thermal_state: string;
  storage_pressure: StorageTier;
  data_mode: DataMode;
  preferred_languages: string[];
  shared_device_mode: boolean;
  updated_at: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// TrustProfile
// ---------------------------------------------------------------------------

/**
 * Firestore path: trust_profiles/{userId}
 */
export interface TrustProfile {
  user_id: string;
  identity_tier: VerificationTier;
  /** 0.0–1.0 */
  community_trust_score: number;
  /** 0.0–1.0; higher = riskier */
  impersonation_risk_score: number;
  donation_permission: boolean;
  dm_risk_level: DmRiskLevel;
  abuse_reports_count: number;
  updated_at: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// FeedRankingSignals
// ---------------------------------------------------------------------------

/**
 * Firestore path: feed_signals/{postId}
 */
export interface FeedRankingSignals {
  post_id: string;
  /** 0.0–1.0 */
  relationship_score: number;
  local_relevance_score: number;
  trust_score: number;
  safety_score: number;
  context_completeness_score: number;
  spiritual_usefulness_score: number;
  freshness_score: number;
  engagement_score: number;
  /** Higher = more viral risk; used to apply friction */
  virality_risk_score: number;
  /** When true, client must show a friction sheet before full expansion */
  context_friction_required: boolean;
}

// ---------------------------------------------------------------------------
// Language types
// ---------------------------------------------------------------------------

/**
 * Embedded in post documents.
 */
export interface ContentLanguageMetadata {
  detected_languages: string[];
  code_switch: boolean;
  /** 0.0–1.0 detection confidence */
  confidence: number;
  original_text: string;
  /** Keyed by BCP-47 locale tag, e.g. { "es": "Hola mundo" } */
  translated_versions: Record<string, string>;
}

/**
 * Firestore path: users/{userId}/language_profile (subcollection doc)
 * or embedded in user profile.
 */
export interface LanguageProfile {
  /** BCP-47 primary locale */
  primary: string;
  secondaries: string[];
  auto_translate: boolean;
  show_original: boolean;
}

// ---------------------------------------------------------------------------
// LowDataPreview
// ---------------------------------------------------------------------------

/**
 * Embedded in post documents for low-data clients.
 */
export interface LowDataPreview {
  title: string;
  text_preview: string;
  thumbnail_url: string | null;
  /** Estimated network cost to load the full item, in kilobytes */
  estimated_data_kb: number;
}

// ---------------------------------------------------------------------------
// CrisisBulletin
// ---------------------------------------------------------------------------

/**
 * Firestore path: crisis_bulletins/{bulletinId}
 */
export interface CrisisBulletin {
  id: string;
  title: string;
  body_text: string;
  severity: BulletinSeverity;
  /** ISO 3166-1 alpha-2 code or "global" */
  region_scope: string;
  expires_at: FirebaseFirestore.Timestamp;
  /** When true, only serve to low-data-mode clients */
  low_data_only: boolean;
  published_by_org_id: string;
}

// ---------------------------------------------------------------------------
// LocalePolicyPack
// ---------------------------------------------------------------------------

/**
 * Firestore path: locale_policy_packs/{localeId}
 */
export interface LocalePolicyPack {
  /** BCP-47 locale identifier */
  locale_id: string;
  sensitive_topics: string[];
  escalation_keywords: string[];
  human_review_required: boolean;
  /** 0.0–1.0; content scoring below this threshold triggers review */
  safety_threshold: number;
}

// ---------------------------------------------------------------------------
// Firestore Path Helpers
// ---------------------------------------------------------------------------

export const PATHS = {
  /** Device capability profile document */
  deviceCapabilityProfile: (uid: string, deviceId: string): string =>
    `devices/${uid}/capability_profiles/${deviceId}`,

  /** All capability profiles for a user */
  deviceCapabilityProfiles: (uid: string): string =>
    `devices/${uid}/capability_profiles`,

  /** Trust profile document */
  trustProfile: (userId: string): string => `trust_profiles/${userId}`,

  /** Feed ranking signals document */
  feedSignals: (postId: string): string => `feed_signals/${postId}`,

  /** Outbox message document */
  messages: (threadId: string, messageId: string): string =>
    `message_threads/${threadId}/messages/${messageId}`,

  /** Outbox message thread */
  messageThread: (threadId: string): string =>
    `message_threads/${threadId}`,

  /** Crisis bulletins collection */
  crisisBulletins: (): string => `crisis_bulletins`,

  /** Single crisis bulletin */
  crisisBulletin: (bulletinId: string): string =>
    `crisis_bulletins/${bulletinId}`,

  /** Locale policy pack document */
  localePolicyPack: (localeId: string): string =>
    `locale_policy_packs/${localeId}`,

  /** All locale policy packs */
  localePolicyPacks: (): string => `locale_policy_packs`,

  /** Language profile embedded doc for a user */
  languageProfile: (userId: string): string =>
    `users/${userId}/settings/language_profile`,

  /** Low data preview embedded in a post */
  post: (postId: string): string => `posts/${postId}`,
} as const;

// ---------------------------------------------------------------------------
// Feature Flag Keys
// ---------------------------------------------------------------------------

export const GR_FLAGS = {
  globalResilienceEnabled: "gr_globalResilienceEnabled",
  lowDataModeEnabled: "gr_lowDataModeEnabled",
  offlineOutboxEnabled: "gr_offlineOutboxEnabled",
  adaptiveMediaEnabled: "gr_adaptiveMediaEnabled",
  voiceTranscriptEnabled: "gr_voiceTranscriptEnabled",
  autoTranslateEnabled: "gr_autoTranslateEnabled",
  sharedDevicePrivacyEnabled: "gr_sharedDevicePrivacyEnabled",
  localLanguagePolicyPacksEnabled: "gr_localLanguagePolicyPacksEnabled",
  antiScamTrustLayerEnabled: "gr_antiScamTrustLayerEnabled",
  verifiedDonationFlowEnabled: "gr_verifiedDonationFlowEnabled",
  crisisBulletinsEnabled: "gr_crisisBulletinsEnabled",
  constitutionalFeedRankingEnabled: "gr_constitutionalFeedRankingEnabled",
} as const;

export type GRFlagKey = (typeof GR_FLAGS)[keyof typeof GR_FLAGS];
