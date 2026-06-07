/**
 * SabbathRouteGuard.tsx — PHASE 2A — State & Gating Engine
 *
 * React component that wraps the app router and enforces Sabbath Mode gating.
 *
 * Props:
 *   - children:     The subtree to render when the route is accessible.
 *   - currentRoute: The policyKey string of the current route
 *                   (matches AmenRoute policyKey values in RestModeGate.swift).
 *   - uid:          Authenticated Firebase user ID.
 *
 * Invariants (from SabbathRouting.ts):
 *   - state === 'active':
 *       • SABBATH_ALWAYS_ALLOWED routes → pass through (safety)
 *       • sabbathConfig.allowedSurfaces routes → pass through
 *       • all other routes → render <SabbathWindowView />
 *   - state === 'steppedOut':
 *       • all routes pass through
 *       • <SabbathBanner /> overlaid on top
 *   - state === 'inactive':
 *       • all routes pass through; no UI injected
 *
 * CRITICAL: This guard NEVER inlines route ids.
 *           It imports SABBATH_ALWAYS_ALLOWED from contracts.
 */

import React from 'react';

// ── Contract imports (never inline route ids) ────────────────────────────────
import { SABBATH_ALWAYS_ALLOWED } from '../contracts/SabbathAllowList';
import { sabbathConfig } from '../contracts/SabbathConfig';

// ── Engine imports ────────────────────────────────────────────────────────────
import { useSabbath } from './useSabbath';

// ── Agent B UI imports ────────────────────────────────────────────────────────
// SabbathWindowView and SabbathBanner are authored by Agent B (Phase 2B).
// We import them by agreed path and do not inline any UI here.
import SabbathWindowView from '../ui/SabbathWindowView';
import SabbathBanner from '../ui/SabbathBanner';

// ─────────────────────────────────────────────────────────────────────────────
// SURFACE ROUTE MAP
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Maps SabbathSurface identifiers (from sabbathConfig.allowedSurfaces) to the
 * policyKey route strings used in the iOS AmenRoute enum.
 *
 * This mapping is the single place in the engine that knows about surface↔route
 * correspondence. It is NOT inlined in gate logic.
 *
 * Phase 2C may extend this map when new surfaces are added.
 */
const SURFACE_ROUTE_MAP: Record<string, string> = {
  scripture: 'scripture',
  prayer: 'prayer',
  bereanGuide: 'berean_guide',
  churchNotes: 'church_notes',
  findChurch: 'find_church',
  spaces: 'spaces',
  familyQuestions: 'family_questions',
  reflection: 'reflection',
};

/**
 * Derive the set of allowed route keys from sabbathConfig.allowedSurfaces.
 * This is computed once at module load — not inside the render path.
 */
const ALLOWED_SURFACE_ROUTES: ReadonlySet<string> = new Set(
  sabbathConfig.allowedSurfaces.map(
    (surface) => SURFACE_ROUTE_MAP[surface] ?? surface,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

export interface SabbathRouteGuardProps {
  /** The subtree to render when the route is accessible. */
  children: React.ReactNode;
  /**
   * The policyKey of the current route.
   * Must match the AmenRoute policyKey string values in RestModeGate.swift.
   * Examples: 'home', 'discovery', 'prayer', 'emergency_support', 'scripture'.
   */
  currentRoute: string;
  /** Authenticated Firebase user ID. */
  uid: string;
}

/**
 * SabbathRouteGuard — enforces the Sabbath Mode gate on every route transition.
 *
 * Must be rendered inside a <SabbathProvider> tree.
 */
export function SabbathRouteGuard({
  children,
  currentRoute,
}: SabbathRouteGuardProps): React.JSX.Element {
  const { state } = useSabbath();

  // ── INACTIVE: full app, no restrictions ──────────────────────────────────
  if (state === 'inactive') {
    return <>{children}</>;
  }

  // ── STEPPED OUT: full app restored, SabbathBanner persists ───────────────
  if (state === 'steppedOut') {
    return (
      <>
        <SabbathBanner />
        {children}
      </>
    );
  }

  // ── ACTIVE: enforce the gate ──────────────────────────────────────────────
  // CRITICAL: We import SABBATH_ALWAYS_ALLOWED from contracts — never inline.

  // 1. Safety surfaces always pass through regardless of anything else.
  const safetyAllowSet = new Set<string>(SABBATH_ALWAYS_ALLOWED);
  if (safetyAllowSet.has(currentRoute)) {
    return <>{children}</>;
  }

  // 2. Sanctioned Sabbath surfaces pass through.
  if (ALLOWED_SURFACE_ROUTES.has(currentRoute)) {
    return <>{children}</>;
  }

  // 3. All other routes → show the Sabbath window (Agent B's component).
  return <SabbathWindowView />;
}

export default SabbathRouteGuard;
