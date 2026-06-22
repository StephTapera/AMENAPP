/**
 * index.ts — Barrel Export (FROZEN CONTRACT)
 * Phase 1 — Contract Freeze Agent
 * Date: 2026-06-07
 *
 * Single entry point for all Sabbath Mode contracts.
 * Phase 2 agents MUST import from this barrel, not from individual files,
 * unless they need a type that would create a circular dependency.
 *
 * DO NOT EDIT after Phase 1 is complete.
 *
 * Usage:
 *   import { SabbathDay, sabbathConfig, SABBATH_ALWAYS_ALLOWED } from '../contracts';
 */

// ── Primitive types ──────────────────────────────────────────────────────────
export type {
  SabbathDay,
  SabbathState,
  SabbathBoundary,
  SabbathSurface,
} from './SabbathTypes';

// ── Data models ──────────────────────────────────────────────────────────────
export type {
  SabbathConfig,
  SabbathSession,
  SabbathReflection,
  SabbathDigest,
} from './SabbathModels';

// ── Runtime config ───────────────────────────────────────────────────────────
export type { SabbathConfigDefaults } from './SabbathConfig';
export { sabbathConfig } from './SabbathConfig';

// ── Safety allow-list ────────────────────────────────────────────────────────
export { SABBATH_ALWAYS_ALLOWED } from './SabbathAllowList';

// ── Routing contract + AI task registry ─────────────────────────────────────
export type {
  SabbathRouteGuardContract,
  SabbathAITask,
} from './SabbathRouting';
export { SABBATH_AI_TASKS } from './SabbathRouting';
