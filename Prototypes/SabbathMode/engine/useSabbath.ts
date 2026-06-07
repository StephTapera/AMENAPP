/**
 * useSabbath.ts — PHASE 2A — State & Gating Engine
 *
 * Custom hook that consumes SabbathContext.
 *
 * Usage:
 *   const { state, config, session, enterStepOut, markSurfaceUsed } = useSabbath();
 *
 * Must be used inside a <SabbathProvider> tree. Throws an invariant error otherwise
 * so that missing provider is caught early in development.
 */

import { useContext } from 'react';
import { SabbathContext, type SabbathContextValue } from './SabbathProvider';

/**
 * Consume the Sabbath state, config, session, and action dispatchers.
 *
 * @throws {Error} If called outside of a <SabbathProvider> tree.
 */
export function useSabbath(): SabbathContextValue {
  const ctx = useContext(SabbathContext);

  if (ctx === null) {
    throw new Error(
      '[useSabbath] Hook must be called inside a <SabbathProvider>. ' +
        'Ensure SabbathProvider wraps the component tree that consumes this hook.',
    );
  }

  return ctx;
}
