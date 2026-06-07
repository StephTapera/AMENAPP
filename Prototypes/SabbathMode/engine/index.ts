/**
 * index.ts — PHASE 2A — State & Gating Engine barrel export
 *
 * All public engine types, components, and functions are re-exported here.
 * Consumers import from 'engine' (this file), never from individual modules.
 */

// ── State Engine (pure TypeScript, no React) ──────────────────────────────
export {
  computeSabbathState,
  getLocalDateString,
  buildSessionKey,
  canStepOut,
} from './SabbathStateEngine';

// ── Provider ──────────────────────────────────────────────────────────────
export {
  SabbathProvider,
  SabbathStepOutError,
} from './SabbathProvider';

export type {
  SabbathContextValue,
  SabbathProviderProps,
} from './SabbathProvider';

// ── Hook ─────────────────────────────────────────────────────────────────
export { useSabbath } from './useSabbath';

// ── Route Guard ───────────────────────────────────────────────────────────
export { SabbathRouteGuard } from './SabbathRouteGuard';

export type { SabbathRouteGuardProps } from './SabbathRouteGuard';
