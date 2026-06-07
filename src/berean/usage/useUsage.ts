/**
 * useUsage.ts — Berean Phase 2C
 *
 * React hook for real-time usage state.
 * Wraps subscribeUsage and handles cleanup on unmount.
 * No localStorage. No writes.
 */

import { useState, useEffect } from 'react';
import { subscribeUsage, UsagePeriod } from './usageService';

// ─────────────────────────────────────────────────────────────────────────────
// Hook
// ─────────────────────────────────────────────────────────────────────────────

export interface UseUsageResult {
  usage: UsagePeriod | null;
  loading: boolean;
  error: string | null;
}

/**
 * Subscribes to the user's Berean usage period via Firestore real-time listener.
 *
 * - `loading` is true until the first snapshot arrives.
 * - `error` is set if the Firestore listener fires an error; usage stays at last
 *   known-good value (or null if no value has arrived yet).
 * - The listener is automatically cleaned up when the component unmounts or
 *   when `userId` changes.
 */
export function useUsage(userId: string): UseUsageResult {
  const [usage, setUsage] = useState<UsagePeriod | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!userId) {
      setLoading(false);
      setError('No userId provided.');
      return;
    }

    setLoading(true);
    setError(null);

    let unsubscribe: (() => void) | undefined;

    try {
      unsubscribe = subscribeUsage(userId, (incoming) => {
        setUsage(incoming);
        setLoading(false);
        setError(null);
      });
    } catch (err) {
      const message =
        err instanceof Error ? err.message : 'Failed to subscribe to usage.';
      setError(message);
      setLoading(false);
    }

    return () => {
      if (unsubscribe) {
        unsubscribe();
      }
    };
  }, [userId]);

  return { usage, loading, error };
}
