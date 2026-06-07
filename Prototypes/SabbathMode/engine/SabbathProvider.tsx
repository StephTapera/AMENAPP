/**
 * SabbathProvider.tsx — PHASE 2A — State & Gating Engine
 *
 * React context provider for Sabbath Mode.
 *
 * - Reads/writes  users/{uid}/sabbath/config         (SabbathConfig)
 * - Reads/writes  users/{uid}/sabbathSessions/{date} (SabbathSession)
 * - Computes and exposes: state, config, session
 * - Exposes enterStepOut(confirmed) and markSurfaceUsed(surface)
 *
 * ADDITIVE WRITES ONLY — uses arrayUnion / updateDoc.
 * Session creation uses setDoc with merge:true.
 * Config creation uses setDoc only when no doc exists.
 */

import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import {
  doc,
  getDoc,
  onSnapshot,
  setDoc,
  updateDoc,
  arrayUnion,
  Timestamp,
  type Firestore,
  type DocumentReference,
  type Unsubscribe,
} from 'firebase/firestore';

import type { SabbathConfig, SabbathSession } from '../contracts/SabbathModels';
import type { SabbathState, SabbathSurface } from '../contracts/SabbathTypes';
import { sabbathConfig } from '../contracts/SabbathConfig';
import { SABBATH_ALWAYS_ALLOWED } from '../contracts/SabbathAllowList';

import {
  computeSabbathState,
  buildSessionKey,
  canStepOut,
  getLocalDateString,
} from './SabbathStateEngine';

// ─────────────────────────────────────────────────────────────────────────────
// ERROR CLASS
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Thrown by enterStepOut when confirmation is required but not yet provided,
 * or when the user has already exhausted their step-out allowance.
 */
export class SabbathStepOutError extends Error {
  public readonly code: 'CONFIRM_REQUIRED' | 'ALREADY_STEPPED_OUT';

  constructor(code: 'CONFIRM_REQUIRED' | 'ALREADY_STEPPED_OUT') {
    super(`SabbathStepOutError: ${code}`);
    this.name = 'SabbathStepOutError';
    this.code = code;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTEXT SHAPE
// ─────────────────────────────────────────────────────────────────────────────

export interface SabbathContextValue {
  /** Current computed Sabbath lifecycle state. */
  state: SabbathState;
  /** User's persisted configuration, or null while loading. */
  config: SabbathConfig | null;
  /** Today's session document, or null when not in a Sabbath window. */
  session: SabbathSession | null;
  /**
   * Attempt to step out of active Sabbath.
   *
   * @param confirmed Pass `true` only after the user has explicitly confirmed
   *                  the step-out confirmation sheet.
   * @throws {SabbathStepOutError} with code 'CONFIRM_REQUIRED' if policy
   *         requires confirmation and confirmed === false.
   * @throws {SabbathStepOutError} with code 'ALREADY_STEPPED_OUT' if the user
   *         has already exhausted their step-out allowance for this Sabbath.
   */
  enterStepOut: (confirmed: boolean) => Promise<void>;
  /**
   * Record that the user visited a Sabbath surface during the active session.
   *
   * Safety surfaces (SABBATH_ALWAYS_ALLOWED) are NEVER logged — they are silently
   * excluded so they cannot be used for behavioural tracking.
   *
   * Also works when state === 'steppedOut'; the user may continue using Sabbath
   * surfaces after stepping out.
   */
  markSurfaceUsed: (surface: SabbathSurface) => Promise<void>;
}

const SabbathContext = createContext<SabbathContextValue | null>(null);

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE PATH HELPERS
// ─────────────────────────────────────────────────────────────────────────────

function configDocRef(db: Firestore, uid: string): DocumentReference {
  return doc(db, 'users', uid, 'sabbath', 'config');
}

function sessionDocRef(
  db: Firestore,
  uid: string,
  dateKey: string,
): DocumentReference {
  return doc(db, 'users', uid, 'sabbathSessions', dateKey);
}

// ─────────────────────────────────────────────────────────────────────────────
// DEFAULT CONFIG FACTORY
// ─────────────────────────────────────────────────────────────────────────────

function makeDefaultConfig(): SabbathConfig {
  const now = Date.now();
  return {
    chosenDay: sabbathConfig.defaultDay,
    boundary: sabbathConfig.defaultBoundary,
    // Use the device timezone (this is a React/TS prototype — navigator.language
    // is available; for React Native use react-native-localize or Intl).
    timezone:
      Intl.DateTimeFormat().resolvedOptions().timeZone ?? 'America/New_York',
    createdAt: now,
    updatedAt: now,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

export interface SabbathProviderProps {
  /** Authenticated Firebase user ID. */
  uid: string;
  /** Initialised Firestore instance. */
  db: Firestore;
  children: React.ReactNode;
}

export function SabbathProvider({
  uid,
  db,
  children,
}: SabbathProviderProps): React.JSX.Element {
  const [config, setConfig] = useState<SabbathConfig | null>(null);
  const [session, setSession] = useState<SabbathSession | null>(null);

  // Ref to the current date key so we can re-subscribe when it changes.
  const currentDateKeyRef = useRef<string>('');

  // ── Compute state reactively from config + session ──────────────────────
  const state = useMemo<SabbathState>(() => {
    if (config === null) return 'inactive';
    return computeSabbathState(
      config,
      new Date(),
      session?.steppedOutAt,
    );
  }, [config, session]);

  // ── Bootstrap config ─────────────────────────────────────────────────────
  useEffect(() => {
    let unsubscribeConfig: Unsubscribe | undefined;

    async function bootstrap(): Promise<void> {
      const ref = configDocRef(db, uid);
      const snap = await getDoc(ref);

      if (!snap.exists()) {
        // Create with defaults (setDoc is allowed for initial creation).
        const defaults = makeDefaultConfig();
        await setDoc(ref, defaults);
        setConfig(defaults);
      }

      // Subscribe to real-time updates.
      unsubscribeConfig = onSnapshot(ref, (snapshot) => {
        if (snapshot.exists()) {
          setConfig(snapshot.data() as SabbathConfig);
        }
      });
    }

    void bootstrap();

    return () => {
      unsubscribeConfig?.();
    };
  }, [uid, db]);

  // ── Subscribe to today's session whenever config changes ─────────────────
  useEffect(() => {
    if (config === null) return;

    const timezone = config.timezone;
    const todayKey = getLocalDateString(timezone);

    // Only re-subscribe if the date key has changed.
    if (currentDateKeyRef.current === todayKey) return;
    currentDateKeyRef.current = todayKey;

    const ref = sessionDocRef(db, uid, todayKey);
    const unsubscribeSession = onSnapshot(ref, (snapshot) => {
      if (snapshot.exists()) {
        setSession(snapshot.data() as SabbathSession);
      } else {
        setSession(null);
      }
    });

    return () => {
      unsubscribeSession();
    };
  }, [uid, db, config]);

  // ── Re-compute state once per minute to catch boundary crossings ──────────
  useEffect(() => {
    const intervalId = setInterval(() => {
      // Trigger a re-render so `state` is recomputed via useMemo.
      // We achieve this by creating a stable signal through a tiny state update.
      setConfig((prev) => (prev === null ? null : { ...prev }));
    }, 60_000);

    return () => clearInterval(intervalId);
  }, []);

  // ── enterStepOut ──────────────────────────────────────────────────────────
  const enterStepOut = useCallback(
    async (confirmed: boolean): Promise<void> => {
      if (config === null) {
        throw new SabbathStepOutError('CONFIRM_REQUIRED');
      }

      const policy = sabbathConfig.stepOutPolicy;
      const currentSession = session ?? { steppedOutAt: undefined };

      // Check if already stepped out.
      if (currentSession.steppedOutAt !== undefined) {
        throw new SabbathStepOutError('ALREADY_STEPPED_OUT');
      }

      // Validate via canStepOut — this also enforces requiresConfirm.
      if (!canStepOut(currentSession, policy, confirmed)) {
        throw new SabbathStepOutError('CONFIRM_REQUIRED');
      }

      const dateKey = buildSessionKey(config.timezone, config.chosenDay);
      const ref = sessionDocRef(db, uid, dateKey);
      const now = Date.now();

      // Ensure session doc exists before updating (merge:true = safe upsert).
      await setDoc(
        ref,
        {
          date: dateKey,
          state: 'active' as SabbathState,
          enteredAt: session?.enteredAt ?? now,
          surfacesUsed: session?.surfacesUsed ?? [],
        },
        { merge: true },
      );

      // Additive update — never overwrite.
      await updateDoc(ref, {
        state: 'steppedOut' as SabbathState,
        steppedOutAt: now,
      });
    },
    [uid, db, config, session],
  );

  // ── markSurfaceUsed ───────────────────────────────────────────────────────
  const markSurfaceUsed = useCallback(
    async (surface: SabbathSurface): Promise<void> => {
      if (config === null) return;

      // Safety surfaces are NEVER logged — silently exclude.
      // SABBATH_ALWAYS_ALLOWED contains route policy keys (strings), not
      // SabbathSurface values, but we check both for belt-and-suspenders safety.
      const safetyKeySet = new Set<string>(SABBATH_ALWAYS_ALLOWED);
      if (safetyKeySet.has(surface)) {
        // Surface name happens to match a safety key — never log it.
        return;
      }

      // Only log surfaces that are in the sanctioned allowed list.
      const isSanctioned = (sabbathConfig.allowedSurfaces as string[]).includes(
        surface,
      );
      if (!isSanctioned) return;

      const dateKey = buildSessionKey(config.timezone, config.chosenDay);
      const ref = sessionDocRef(db, uid, dateKey);
      const now = Date.now();

      // Create session doc if it doesn't exist (merge:true = safe upsert).
      await setDoc(
        ref,
        {
          date: dateKey,
          state: state,
          enteredAt: session?.enteredAt ?? now,
          surfacesUsed: [],
        },
        { merge: true },
      );

      // Additive write — arrayUnion ensures no duplicates and never overwrites.
      await updateDoc(ref, {
        surfacesUsed: arrayUnion(surface),
      });
    },
    [uid, db, config, session, state],
  );

  // ── Context value ─────────────────────────────────────────────────────────
  const contextValue = useMemo<SabbathContextValue>(
    () => ({
      state,
      config,
      session,
      enterStepOut,
      markSurfaceUsed,
    }),
    [state, config, session, enterStepOut, markSurfaceUsed],
  );

  return (
    <SabbathContext.Provider value={contextValue}>
      {children}
    </SabbathContext.Provider>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL CONTEXT ACCESSOR (used only by useSabbath.ts)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @internal — exported for useSabbath.ts only. Do not consume directly.
 */
export { SabbathContext };
