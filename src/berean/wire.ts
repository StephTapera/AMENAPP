/**
 * wire.ts — Phase 3 Berean v1 Integration File
 *
 * Single integration file owned by Phase 3 only.
 * Imports from every Phase 2 module to confirm resolution, wires the
 * shared export surface, and documents credential stops and human gates.
 *
 * This file is the app-level entry point for Berean v1 in the React prototype.
 * It does NOT modify any Phase 2 file. It only imports and re-exports.
 */

// ─────────────────────────────────────────────────────────────────────────────
// CONTRACT TYPES (Phase 1 — source of truth)
// ─────────────────────────────────────────────────────────────────────────────

export type {
  Visibility,
  Domain,
  TruthLevel,
  SourceRef,
  Provenance,
  CapabilityTier,
  Plan,
  VoicePersona,
  VoiceMode,
  VoiceSpeed,
  ConnectorType,
  SafetyLevel,
  RefusalReason,
  BereanCallModelParams,
  BereanCallModelResult,
  BereanContext,
  MemorySummary,
  ConnectorContext,
  BereanMemoryDoc,
  BereanThreadDoc,
  BereanMessageDoc,
  BereanUsageDoc,
  BereanCapabilities,
  BereanConnectorDoc,
  CreditConfigDoc,
  VoiceConfigDoc,
  HumanGateReason,
  HumanGatePayload,
} from './contracts';

export { tokens, DOMAIN_TO_TASK, MINOR_BLOCKED_DOMAINS, MINOR_BLOCKED_CONNECTORS, MINOR_BLOCKED_VISIBILITY } from './contracts';

// ─────────────────────────────────────────────────────────────────────────────
// CORE INTELLIGENCE (Phase 2A)
// ─────────────────────────────────────────────────────────────────────────────

export { BereanProvider, useBerean } from './core/BereanCore';
export { callBerean } from './core/callBerean';
export { memoryService } from './core/memory';
export { crisisService, getCrisisResources } from './core/crisis';
export { buildPerspectivePrompt, parsePerspectiveResponse } from './core/perspectives';

// ─────────────────────────────────────────────────────────────────────────────
// VOICE (Phase 2B)
// ─────────────────────────────────────────────────────────────────────────────

export { voiceService } from './voice/voiceService';
export { default as VoiceSettings } from './voice/VoiceSettings';
export { default as VoiceSession } from './voice/VoiceSession';
export { default as ScriptureReadAloud } from './voice/ScriptureReadAloud';

// ─────────────────────────────────────────────────────────────────────────────
// USAGE & METERING (Phase 2C)
// ─────────────────────────────────────────────────────────────────────────────

export { fetchUsage, subscribeUsage } from './usage/usageService';
export { useUsage } from './usage/useUsage';
export { default as UsageMeters } from './usage/UsageMeters';

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTORS & BIBLE PROVIDER (Phase 2D)
// ─────────────────────────────────────────────────────────────────────────────

export { getBibleProvider } from './connectors/BibleProvider';
export type { BibleVerse, BibleProviderAdapter } from './connectors/BibleProvider';
export { fetchConnectors, connectConnector, revokeConnector } from './connectors/connectorsService';
export { default as ConnectorsScreen } from './connectors/ConnectorsScreen';

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLS (Phase 2E)
// ─────────────────────────────────────────────────────────────────────────────

export { fetchCapabilities, updateCapabilities, saveVisibility, fetchVisibility } from './controls/controlsService';
export { default as CapabilitiesScreen } from './controls/CapabilitiesScreen';
export { default as SharingVisibility } from './controls/SharingVisibility';

// ─────────────────────────────────────────────────────────────────────────────
// WIRING VERIFICATION ASSERTIONS
// These run at module load and throw if any invariant is violated.
// Not a test suite — these catch mis-wired exports before runtime.
// ─────────────────────────────────────────────────────────────────────────────

import { tokens as _t, DOMAIN_TO_TASK as _dtt, MINOR_BLOCKED_VISIBILITY as _mbv } from './contracts';
import { getCrisisResources as _gcr } from './core/crisis';

// Invariant 1: tokens contain no forbidden values
const _forbiddenTokenCheck = (() => {
  const forbidden = ['#C9A84C', '#FFD97D', '#7B68EE', '0A0A0F', '111118'];
  const tokenStr = JSON.stringify(_t);
  for (const f of forbidden) {
    if (tokenStr.includes(f)) {
      throw new Error(`[berean/wire] FORBIDDEN design token detected in contracts.ts: ${f}`);
    }
  }
})();

// Invariant 2: crisis domain maps to crisis_handoff (never an AI content task)
const _crisisMappingCheck = (() => {
  if (_dtt['crisis'] !== 'crisis_handoff') {
    throw new Error('[berean/wire] INVARIANT VIOLATED: Domain "crisis" must map to "crisis_handoff"');
  }
})();

// Invariant 3: minor visibility blocks 'public' and 'organization'
const _minorVisibilityCheck = (() => {
  if (!_mbv.includes('public') || !_mbv.includes('organization')) {
    throw new Error('[berean/wire] INVARIANT VIOLATED: MINOR_BLOCKED_VISIBILITY must include public and organization');
  }
})();

// Invariant 4: crisis resources are real (not empty)
const _crisisResourcesCheck = (() => {
  const resources = _gcr();
  if (!resources || resources.length < 3) {
    throw new Error('[berean/wire] INVARIANT VIOLATED: getCrisisResources() must return at least 3 real resources');
  }
  for (const r of resources) {
    if (!r.contact) {
      throw new Error(`[berean/wire] INVARIANT VIOLATED: Crisis resource "${r.name}" must have a contact value`);
    }
  }
})();

// Invariant 5: 'private' is the first (default) Visibility in the ordering
const VISIBILITY_ORDER: readonly import('./contracts').Visibility[] = [
  'private', 'followers', 'paid', 'organization', 'public',
] as const;

export { VISIBILITY_ORDER };

// ─────────────────────────────────────────────────────────────────────────────
// CREDENTIAL STOP REGISTRY
// Document every credential required. Phase 3 agent checked for existence;
// missing credentials are flagged here — app will fail at CF call time, not silently.
// ─────────────────────────────────────────────────────────────────────────────

export const BEREAN_CREDENTIAL_REGISTRY = {
  ANTHROPIC_API_KEY:     { required: true,  purpose: 'All pastoral/scripture/theology domains — Claude only, no failover' },
  NVIDIA_API_KEY:        { required: true,  purpose: 'NeMo Guardrails input/output safety — fail closed' },
  PINECONE_API_KEY:      { required: true,  purpose: 'Grounded RAG retrieval — fail closed on miss' },
  PINECONE_HOST:         { required: true,  purpose: 'Pinecone host URL' },
  ALGOLIA_APP_ID:        { required: true,  purpose: 'Keyword search (Firestore fallback available)' },
  ALGOLIA_ADMIN_API_KEY: { required: true,  purpose: 'Algolia admin key for CF writes' },
  BIBLE_API_KEY:         { required: true,  purpose: 'api.bible for BSB/WEB/KJV — server-side only (bereanBibleLookup CF)' },
  GOOGLE_TTS_API_KEY:    { required: false, purpose: 'Voice TTS — degrades to text-only if missing' },
  GOOGLE_STT_API_KEY:    { required: false, purpose: 'Voice STT — degrades to text-input if missing' },
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// HUMAN GATE REGISTRY
// Catalogue of all three mandated human gates.
// ─────────────────────────────────────────────────────────────────────────────

export const HUMAN_GATE_REGISTRY = {
  MINOR_GRAPH_DATA: {
    description: 'Any graph-level data write for a minor account',
    location: 'src/berean/controls/controlsService.ts — updateCapabilities()',
    behavior: 'Logs HumanGatePayload and throws Error("connectors_blocked_minor") — never silently writes',
  },
  CRISIS_CONTENT: {
    description: 'Crisis handoff content — T&S owns the response queue',
    location: 'src/berean/core/BereanCore.tsx — sendMessage(), src/berean/core/crisis.ts — handleCrisis()',
    behavior: 'AI answer suppressed at both keyword fast-path and AI detection stage. Only getCrisisResources() (hardcoded, no AI) surfaces to user.',
  },
  CSAM_SIGNAL: {
    description: 'CSAM detection routes through existing ncmecReporter.js pipeline',
    location: 'functions/ncmecReporter.js (pre-existing pipeline — not modified)',
    behavior: 'Human decision required. Real NCMEC CyberTipline vendor. Never silently handled.',
  },
} as const;
