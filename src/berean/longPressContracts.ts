/**
 * longPressContracts.ts — Long-Press Intelligence Layer ("Press to Ask Berean")
 * Wave 0 contracts. Frozen after commit; behavior in subsequent waves.
 *
 * AIL rule: TypeScript is source of truth; Swift mirrors in
 * AMENAPP/AIIntelligence/LongPressIntelligenceContracts.swift.
 *
 * ARCHITECTURE INVARIANTS:
 *   - ONE BereanDepth enum app-wide (defined in spiritualIntelligenceContracts.ts)
 *   - ONE LongPressIntelligenceMenu component; no per-screen reimplementation
 *   - Entry surface into existing Berean (mode × depth); does NOT fork Berean
 *   - Adding an object type = registering its actions; no bespoke menus
 */

import type {
  BereanDepth,
  BereanPostureMode,
  PrivacyCoreZone,
} from './spiritualIntelligenceContracts';

// ─────────────────────────────────────────────────────────────────────────────
// OBJECT CONTEXT (captured on press — tells Berean what it is reasoning about)
// ─────────────────────────────────────────────────────────────────────────────

export type LongPressObjectType =
  | 'post'
  | 'comment'
  | 'verse'
  | 'creator'
  | 'community'
  | 'video'
  | 'event'
  | 'resource'
  | 'profile_avatar'
  | 'message'
  | 'text_selection';

export type LongPressSourceSurface =
  | 'feed'
  | 'creator_page'
  | 'community'
  | 'scripture_reader'
  | 'conversation'
  | 'search'
  | 'notification'
  | 'spotlight';

export type LongPressPayload =
  | { kind: 'post';           text: string; authorId: string }
  | { kind: 'comment';        text: string; authorId: string; threadId: string }
  | { kind: 'verse';          reference: string; translation: string; text: string }
  | { kind: 'creator';        creatorId: string; displayName: string }
  | { kind: 'community';      communityId: string; name: string }
  | { kind: 'video';          videoId: string; title: string; durationSeconds?: number }
  | { kind: 'event';          eventId: string; title: string }
  | { kind: 'resource';       resourceId: string; title: string; format: string }
  | { kind: 'profile_avatar'; userId: string; displayName: string }
  | { kind: 'message';        messageId: string; text: string }
  | { kind: 'text_selection'; selectedText: string; sourceObjectId: string; sourceObjectType: string };

export interface BereanObjectContext {
  objectType: LongPressObjectType;
  objectId: string;
  /** Only the fields relevant to this objectType are populated */
  payload: LongPressPayload;
  sourceSurface: LongPressSourceSurface;
  /** Captured on press, not on action tap — warmable while menu is open */
  capturedAt: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// INTELLIGENCE ACTION DESCRIPTOR
// Maps to existing Berean posture modes where relevant:
//   explain → ask | compare → discern | generate_study → build
//   apply → reflect | safety → guard | non-AI → null
// ─────────────────────────────────────────────────────────────────────────────

export type IntelligenceActionCategory =
  | 'quick'        // Non-AI: Reply, Save, Share
  | 'smart'        // AI-powered via Berean
  | 'relationship' // Social: Follow, View profile
  | 'safety';      // Report, Hide, Mute → GUARDIAN

export interface IntelligenceAction {
  id: string;
  label: string;
  /** Identical surface to label; required for VoiceOver rotor */
  accessibilityLabel: string;
  category: IntelligenceActionCategory;
  /** null for non-AI actions */
  bereanMode: BereanPostureMode | null;
  /** Show depth dial only when true */
  usesDepthDial: boolean;
  /** All scripture output must pass Citation Integrity when true */
  requiresCitationIntegrity: boolean;
  /** Route output through GUARDIAN when true */
  requiresGuardianModeration: boolean;
  privacyZone: PrivacyCoreZone;
  applicableObjectTypes: LongPressObjectType[];
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION REGISTRY (extension model)
// Adding a new object type = adding an ActionRegistryEntry.
// No per-screen menu implementations.
// ─────────────────────────────────────────────────────────────────────────────

export interface ActionRegistryEntry {
  objectType: LongPressObjectType;
  actions: IntelligenceAction[];
}

export type ActionRegistry = ActionRegistryEntry[];

// ─────────────────────────────────────────────────────────────────────────────
// DEPTH DIAL STATE (manual override of auto-selected depth)
// ONE unified dial; one BereanDepth enum; defaults to IntentSwitch's choice.
// ─────────────────────────────────────────────────────────────────────────────

export interface DepthDialState {
  /** Proposed by Intent Switch */
  autoSelectedDepth: BereanDepth;
  /** Set when user nudges the dial */
  manualOverride?: BereanDepth;
  /** = manualOverride ?? autoSelectedDepth */
  effectiveDepth: BereanDepth;
  threadId: string;
  /** Always true — override is sticky per-thread */
  readonly overrideRememberedPerThread: true;
}

// ─────────────────────────────────────────────────────────────────────────────
// ADAPTIVE REACH (on-device only; low privacy zone; user-resettable)
// Frequently used actions migrate toward thumb. Never exported from device.
// ─────────────────────────────────────────────────────────────────────────────

export interface AdaptiveReachRecord {
  actionId: string;
  objectType: LongPressObjectType;
  tapCount: number;
  lastTappedAt: number;
  /** Invariants — compile-time readable */
  readonly _onDeviceOnly: true;
  readonly _userResettable: true;
  readonly _neverExported: true;
  readonly _privacyZone: 'functional';
}
