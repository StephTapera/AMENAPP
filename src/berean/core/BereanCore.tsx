/**
 * BereanCore.tsx — Berean Phase 2A
 *
 * React context provider + hook for the Berean v1 faith assistant.
 *
 * Provides:
 *  - BereanContext (capabilities, plan, safetyLevel, minorScoped)
 *  - sendMessage(): crisis-gated, memory-augmented callBerean wrapper
 *  - memoryService: read/write/summarize memory
 *  - crisisService: detection + resource routing
 *  - updateCapabilities(): patch BereanCapabilities live
 *
 * Design invariants:
 *  1. Crisis path ALWAYS suppresses AI answer — sendMessage() returns a
 *     hard-blocked BereanCallModelResult when crisis is detected.
 *  2. minorScoped is read from the Firebase Auth ID token claim, not Firestore.
 *  3. Capabilities are loaded from Firestore `berean/{uid}/capabilities` on mount.
 *  4. No localStorage / sessionStorage.
 *  5. FORBIDDEN tokens: dark backgrounds, gold colors, Cormorant Garamond.
 *     Font: SF system font only.
 *
 * FROZEN: 2026-06-07
 * OWNER: Phase 2A Core Agent
 */

import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from 'react';

import { getAuth, onIdTokenChanged } from 'firebase/auth';
import {
  getFirestore,
  doc,
  getDoc,
  setDoc,
  serverTimestamp,
} from 'firebase/firestore';

import type {
  BereanCapabilities,
  BereanCallModelResult,
  BereanContext,
  Domain,
  Plan,
  SafetyLevel,
} from '../contracts';

import {
  DOMAIN_TO_TASK,
  MINOR_BLOCKED_DOMAINS,
} from '../contracts';

import { callBerean } from './callBerean';
import { memoryService } from './memory';
import { crisisService } from './crisis';

// ─────────────────────────────────────────────────────────────────────────────
// Default capabilities (all off — loaded from Firestore on mount)
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_CAPABILITIES: BereanCapabilities = {
  memory: false,
  proactive: false,
  voice: false,
  minorScoped: false,
  connectors: {
    bible: false,
    church_calendar: false,
    giving: false,
    sermon_library: false,
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// Crisis suppression result — returned when AI answer must not surface
// ─────────────────────────────────────────────────────────────────────────────

function crisisSuppressedResult(): BereanCallModelResult {
  return {
    text: '',
    provenance: { sources: [], truthLevel: 'refused' },
    refusal: 'crisis_handoff',
    blocked: true,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Minor-blocked result
// ─────────────────────────────────────────────────────────────────────────────

function minorBlockedResult(): BereanCallModelResult {
  return {
    text: '',
    provenance: { sources: [], truthLevel: 'refused' },
    refusal: 'minor_scope',
    blocked: true,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Context value interface
// ─────────────────────────────────────────────────────────────────────────────

export interface BereanContextValue {
  context: BereanContext;
  sendMessage: (input: string, domain: Domain) => Promise<BereanCallModelResult>;
  memoryService: typeof memoryService;
  crisisService: typeof crisisService;
  updateCapabilities: (caps: Partial<BereanCapabilities>) => void;
}

// ─────────────────────────────────────────────────────────────────────────────
// React context
// ─────────────────────────────────────────────────────────────────────────────

const BereanReactContext = createContext<BereanContextValue | null>(null);

// ─────────────────────────────────────────────────────────────────────────────
// BereanProvider
// ─────────────────────────────────────────────────────────────────────────────

interface BereanProviderProps {
  children: React.ReactNode;
  userId: string;
  plan: Plan;
}

export const BereanProvider: React.FC<BereanProviderProps> = ({
  children,
  userId,
  plan,
}) => {
  const [capabilities, setCapabilities] =
    useState<BereanCapabilities>(DEFAULT_CAPABILITIES);
  const [minorScoped, setMinorScoped] = useState<boolean>(false);
  const [capabilitiesLoaded, setCapabilitiesLoaded] = useState(false);

  // ── Derive safetyLevel from plan + minorScoped ───────────────────────────
  const safetyLevel: SafetyLevel = minorScoped
    ? 'minor'
    : plan === 'free'
    ? 'standard'
    : 'pastoral';

  // ── Build the current BereanContext ───────────────────────────────────────
  const context: BereanContext = {
    userId,
    plan,
    safetyLevel,
    minorScoped,
    capabilities,
  };

  // ── Load minorScoped from Firebase Auth ID token claim ───────────────────
  useEffect(() => {
    const auth = getAuth();

    const unsubscribe = onIdTokenChanged(auth, async (user) => {
      if (!user) {
        setMinorScoped(false);
        return;
      }
      try {
        const tokenResult = await user.getIdTokenResult();
        const claim = tokenResult.claims['minorScoped'];
        setMinorScoped(claim === true || claim === 'true');
      } catch {
        // Default to false on token read failure — not a minor-scoped session.
        setMinorScoped(false);
      }
    });

    return () => unsubscribe();
  }, []);

  // ── Load capabilities from Firestore `berean/{uid}/capabilities` ─────────
  useEffect(() => {
    if (!userId) return;

    async function loadCapabilities() {
      try {
        const db = getFirestore();
        const capsRef = doc(db, 'berean', userId, 'capabilities', 'current');
        const snap = await getDoc(capsRef);

        if (snap.exists()) {
          const data = snap.data() as Partial<BereanCapabilities>;
          setCapabilities((prev) => ({
            ...prev,
            ...data,
            // minorScoped capability mirrors the Auth token claim — Firestore
            // cannot override what the token says.
            minorScoped: prev.minorScoped,
            connectors: {
              ...prev.connectors,
              ...(data.connectors ?? {}),
            },
          }));
        }
      } catch {
        // Fail open — default capabilities applied; non-blocking.
      } finally {
        setCapabilitiesLoaded(true);
      }
    }

    loadCapabilities();
  }, [userId]);

  // ── updateCapabilities — patches live + persists to Firestore ────────────
  const updateCapabilities = useCallback(
    (caps: Partial<BereanCapabilities>) => {
      setCapabilities((prev) => {
        const next: BereanCapabilities = {
          ...prev,
          ...caps,
          // minorScoped is Auth-token-derived — never patchable via this API
          minorScoped: prev.minorScoped,
          connectors: {
            ...prev.connectors,
            ...(caps.connectors ?? {}),
          },
        };

        // Persist asynchronously — fire-and-forget; state update is synchronous.
        try {
          const db = getFirestore();
          const capsRef = doc(db, 'berean', userId, 'capabilities', 'current');
          setDoc(capsRef, { ...next, updatedAt: serverTimestamp() }, { merge: true }).catch(
            () => {
              // Non-fatal — in-memory state is still updated.
            },
          );
        } catch {
          // Non-fatal.
        }

        return next;
      });
    },
    [userId],
  );

  // ── sendMessage — the main pipeline ──────────────────────────────────────
  const sendMessage = useCallback(
    async (input: string, domain: Domain): Promise<BereanCallModelResult> => {
      // ── Minor scope guard ──────────────────────────────────────────────
      if (minorScoped && MINOR_BLOCKED_DOMAINS.includes(domain)) {
        return minorBlockedResult();
      }

      // ── Fast crisis keyword pre-screen (synchronous) ──────────────────
      const crisisSignalFast = crisisService.detectCrisis(input);

      if (crisisSignalFast) {
        // Call AI detection CF for confirmation; AI answer suppressed either way.
        // HUMAN GATE: T&S owns the crisis response queue. AI answer suppressed.
        await crisisService.handleCrisis(userId, input);
        return crisisSuppressedResult();
      }

      // ── Fetch memory context if capability enabled ─────────────────────
      let memoryContext = context.memoryContext;
      if (capabilities.memory && capabilitiesLoaded) {
        try {
          memoryContext = await memoryService.fetchMemoryContext(userId, domain);
        } catch {
          // Fail open — proceed without memory context.
          memoryContext = [];
        }
      }

      // ── Build enriched context for this call ───────────────────────────
      const enrichedContext: BereanContext = {
        ...context,
        memoryContext,
      };

      // ── Route through callBerean ───────────────────────────────────────
      const result = await callBerean({
        task: domain,
        input,
        context: enrichedContext,
      });

      // ── Post-call crisis check on AI response (output may signal crisis) ─
      // The NVIDIA output guard in the router handles most cases; this is a
      // defence-in-depth check on the returned text before it reaches the UI.
      if (result.text && crisisService.detectCrisis(result.text)) {
        // HUMAN GATE: T&S owns the crisis response queue. AI answer suppressed.
        await crisisService.handleCrisis(userId, result.text);
        return crisisSuppressedResult();
      }

      return result;
    },
    [
      userId,
      minorScoped,
      capabilities,
      capabilitiesLoaded,
      context,
    ],
  );

  // ── Context value ─────────────────────────────────────────────────────────
  const value: BereanContextValue = {
    context,
    sendMessage,
    memoryService,
    crisisService,
    updateCapabilities,
  };

  return (
    <BereanReactContext.Provider value={value}>
      {children}
    </BereanReactContext.Provider>
  );
};

// ─────────────────────────────────────────────────────────────────────────────
// useBerean — consumer hook
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns the BereanContextValue. Must be called inside a <BereanProvider>.
 * Throws if called outside the provider tree so misconfigured consumers
 * fail fast at development time.
 */
export function useBerean(): BereanContextValue {
  const ctx = useContext(BereanReactContext);
  if (!ctx) {
    throw new Error(
      'useBerean() must be called inside a <BereanProvider>. ' +
        'Wrap your component tree with <BereanProvider userId={uid} plan={plan}>.',
    );
  }
  return ctx;
}
