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
 *   - onSurfaceSelect: (optional) forwarded to SabbathWindowView when gate is
 *                   active. If omitted a no-op is used so the guard is always
 *                   renderable without a parent wiring handler.
 *   - onStepOut:    (optional) forwarded to SabbathWindowView. Called after the
 *                   BlessAndCloseSheet confirms the step-out intent; the guard
 *                   also calls enterStepOut(true) internally.
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

import React, { useCallback } from 'react';
import type { SabbathSurface } from '../contracts/SabbathTypes';

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
  /**
   * Called when the user selects a Sabbath surface inside SabbathWindowView.
   * Optional — defaults to a no-op so the guard is self-contained without
   * requiring parent wiring. The parent should wire this to its own router.
   */
  onSurfaceSelect?: (surface: SabbathSurface) => void;
  /**
   * Called after the user confirms step-out in BlessAndCloseSheet.
   * Optional — the guard calls enterStepOut(true) internally; this gives
   * the parent an opportunity to handle any additional routing logic.
   */
  onStepOut?: () => void;
}

/**
 * SabbathRouteGuard — enforces the Sabbath Mode gate on every route transition.
 *
 * Must be rendered inside a <SabbathProvider> tree.
 */
export function SabbathRouteGuard({
  children,
  currentRoute,
  onSurfaceSelect,
  onStepOut,
}: SabbathRouteGuardProps): React.JSX.Element {
  const { state, session, enterStepOut } = useSabbath();

  // Stable no-op default for onSurfaceSelect so SabbathWindowView always
  // receives a valid function regardless of parent wiring.
  const handleSurfaceSelect = useCallback(
    (surface: SabbathSurface) => {
      onSurfaceSelect?.(surface);
    },
    [onSurfaceSelect],
  );

  // Step-out handler: call enterStepOut(true) on the engine, then notify parent.
  const handleStepOut = useCallback(async () => {
    try {
      await enterStepOut(true);
    } catch {
      // enterStepOut throws SabbathStepOutError if already stepped out or
      // confirmation was not provided — both are safe to swallow here because
      // BlessAndCloseSheet already required explicit confirmation before calling.
    }
    onStepOut?.();
  }, [enterStepOut, onStepOut]);

  // ── INACTIVE: full app, no restrictions ──────────────────────────────────
  if (state === 'inactive') {
    return <>{children}</>;
  }

  // ── STEPPED OUT: full app restored, SabbathBanner persists ───────────────
  if (state === 'steppedOut') {
    // steppedOutAt comes from the session doc. Fall back to current time so
    // the banner always receives a valid number (it uses the value for caller
    // tracking only — never displays it).
    const steppedOutAt = session?.steppedOutAt ?? Date.now();
    return (
      <>
        <SabbathBanner steppedOutAt={steppedOutAt} />
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
  //    Pass required props so SabbathWindowView is fully wired.
  return (
    <SabbathWindowView
      onSurfaceSelect={handleSurfaceSelect}
      onStepOut={handleStepOut}
    />
  );
}

export default SabbathRouteGuard;
