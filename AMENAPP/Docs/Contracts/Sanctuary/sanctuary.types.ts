// FROZEN - SANCTUARY Wave 0 Living Video contracts.
// Keep field-for-field parity with Shared/Contracts/SanctuaryModels.swift.
// Frozen on 2026-06-12.

export const SANCTUARY_CONTRACTS_VERSION = "2026-06-12-wave0-v1" as const;

export const sanctuaryFeatureFlagKeys = [
  "sanctuary_core",
  "sanctuary_layers",
  "sanctuary_thread",
  "sanctuary_reactions",
  "sanctuary_watch_together",
  "sanctuary_selah",
  "sanctuary_ask_moment",
  "sanctuary_journey",
  "sanctuary_search",
] as const;

export type SanctuaryFeatureFlagKey = typeof sanctuaryFeatureFlagKeys[number];

export interface SanctuaryUserRef {
  uid: string;
  displayName?: string | null;
  avatarURL?: string | null;
}

export interface SanctuaryC2PAProvenance {
  manifestURL?: string | null;
  assertionHash?: string | null;
  signer?: string | null;
  verified: boolean;
  capturedAt?: string | null;
}

export type TranscriptStatus = "pending" | "processing" | "ready" | "failed";
export type LivingVideoContentType = "sermon" | "podcast" | "worship" | "testimony" | "study" | "event";

export interface LivingVideo {
  id: string;
  mediaURL: string;
  transcriptStatus: TranscriptStatus;
  scriptureAnchors: ScriptureAnchor[];
  layerRefs: SanctuaryLayerRef[];
  provenance: SanctuaryC2PAProvenance;
  contentType: LivingVideoContentType;
}

export type ScriptureAnchorSource = "ai" | "creator" | "community";

export interface ScriptureAnchor {
  verseRef: string;
  timestampMs: number;
  confidence: number;
  source: ScriptureAnchorSource;
}

export type VideoLayerType = "creator_notes" | "scripture" | "community_insights" | "ai_context" | "group_private";
export type VideoLayerVisibility = "owner_only" | "creator" | "community" | "group_private" | "public_read";

export interface SanctuaryLayerRef {
  id: string;
  type: VideoLayerType;
}

export interface VideoLayer {
  id: string;
  type: VideoLayerType;
  visibility: VideoLayerVisibility;
  blocks: SanctuaryLayerBlock[];
}

export type SanctuaryLayerBlockKind = "text" | "scripture" | "note" | "question" | "citation" | "prayer";

export interface SanctuaryLayerBlock {
  id: string;
  kind: SanctuaryLayerBlockKind;
  text: string;
  timestampMs?: number | null;
  sourceRef?: string | null;
}

export type SacredReactionType = "amen" | "convicted" | "encouraged" | "need_prayer" | "studying_this" | "saved";

export interface SacredReaction {
  type: SacredReactionType;
  timestampMs: number;
  userRef: SanctuaryUserRef;
}

export type WatchRoomState = "playing" | "paused" | "prayer";

export interface WatchRoom {
  id: string;
  hostRef: SanctuaryUserRef;
  memberOrbs: SanctuaryUserRef[];
  playheadMs: number;
  state: WatchRoomState;
}

export type SelahCardType = "verse" | "prompt" | "silence";

export interface SelahCard {
  id: string;
  type: SelahCardType;
  durationMs: number;
  verseRef?: string | null;
  prompt?: string | null;
}

export type SanctuaryInteractionType = "watch_complete" | "highlight" | "question" | "note" | "reaction" | "prayer";

export interface SanctuaryInteraction {
  id: string;
  type: SanctuaryInteractionType;
  videoRef: string;
  timestampMs?: number | null;
  createdAt: string;
  metadata: Record<string, unknown>;
}

export interface JourneyNode {
  id: string;
  videoRef: string;
  interactions: SanctuaryInteraction[];
  themeEmbeddingRef: string;
  linkedNodes: string[];
}
