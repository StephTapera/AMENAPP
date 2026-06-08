/**
 * controlsService.ts — Berean v1 Phase 2E
 * Capabilities and visibility persistence via Firestore client SDK.
 *
 * OWNER: Phase 2E Controls Agent
 * Contract types imported from contracts.ts — never redefine.
 */

import {
  getFirestore,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from 'firebase/firestore';
import {
  BereanCapabilities,
  Visibility,
  HumanGatePayload,
} from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// SAFE DEFAULTS
// ─────────────────────────────────────────────────────────────────────────────

const SAFE_DEFAULTS: BereanCapabilities = {
  memory: true,
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
// HUMAN GATE — minor graph data
// ─────────────────────────────────────────────────────────────────────────────

function emitHumanGate(payload: HumanGatePayload): void {
  // HUMAN GATE: minor graph data requires T&S approval. See contracts.ts HumanGatePayload.
  // This function logs the gate payload and must NOT proceed with the write.
  // T&S review queue integration is a manual deploy step — do not auto-implement.
  console.error('[HUMAN_GATE]', JSON.stringify(payload));
}

function buildHumanGatePayload(
  userId: string,
  operation: string,
): HumanGatePayload {
  return {
    reason: 'MINOR_GRAPH_DATA',
    userId,
    timestamp: new Date().toISOString(),
    context: {
      operation,
      note: 'Attempted write of graph-level data for minor-scoped account.',
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// CAPABILITIES
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetch capabilities for a user.
 * Returns safe defaults if the document does not yet exist.
 */
export async function fetchCapabilities(
  userId: string,
): Promise<BereanCapabilities> {
  const db = getFirestore();
  const ref = doc(db, 'berean', userId, 'capabilities', 'settings');
  const snap = await getDoc(ref);

  if (!snap.exists()) {
    return { ...SAFE_DEFAULTS, connectors: { ...SAFE_DEFAULTS.connectors } };
  }

  const data = snap.data() as Partial<BereanCapabilities>;

  // Merge with safe defaults so any new fields added to the contract
  // are always present even on older stored documents.
  return {
    memory: data.memory ?? SAFE_DEFAULTS.memory,
    proactive: data.proactive ?? SAFE_DEFAULTS.proactive,
    voice: data.voice ?? SAFE_DEFAULTS.voice,
    minorScoped: data.minorScoped ?? SAFE_DEFAULTS.minorScoped,
    connectors: {
      bible: data.connectors?.bible ?? SAFE_DEFAULTS.connectors.bible,
      church_calendar:
        data.connectors?.church_calendar ??
        SAFE_DEFAULTS.connectors.church_calendar,
      giving: data.connectors?.giving ?? SAFE_DEFAULTS.connectors.giving,
      sermon_library:
        data.connectors?.sermon_library ??
        SAFE_DEFAULTS.connectors.sermon_library,
    },
  };
}

/**
 * Persist a partial capabilities update.
 *
 * Minor guard:
 *   - If the current stored minorScoped is true (or the patch itself sets it
 *     to true), any attempt to write to `connectors` is rejected with
 *     Error('connectors_blocked_minor').
 *   - Any write that would touch graph-level data for a minor account is
 *     intercepted, logged as a HumanGatePayload, and rejected.
 */
export async function updateCapabilities(
  userId: string,
  patch: Partial<BereanCapabilities>,
): Promise<void> {
  const db = getFirestore();
  const ref = doc(db, 'berean', userId, 'capabilities', 'settings');

  // Fetch current state to determine minorScoped status.
  const current = await fetchCapabilities(userId);
  const effectiveMinorScoped =
    patch.minorScoped !== undefined ? patch.minorScoped : current.minorScoped;

  // HUMAN GATE: any write that touches graph-level connector data for a minor
  // account must be stopped and routed to T&S review.
  if (effectiveMinorScoped && patch.connectors !== undefined) {
    // HUMAN GATE: minor graph data requires T&S approval. See contracts.ts HumanGatePayload.
    emitHumanGate(buildHumanGatePayload(userId, 'updateCapabilities:connectors'));
    throw new Error('connectors_blocked_minor');
  }

  // Minor guard: connector writes blocked when account is minor-scoped.
  if (current.minorScoped && patch.connectors !== undefined) {
    // HUMAN GATE: minor graph data requires T&S approval. See contracts.ts HumanGatePayload.
    emitHumanGate(buildHumanGatePayload(userId, 'updateCapabilities:connectors'));
    throw new Error('connectors_blocked_minor');
  }

  // Flatten the patch into Firestore dot-notation update to avoid overwriting
  // fields not included in the patch.
  const firestorePatch: Record<string, unknown> = {};

  if (patch.memory !== undefined) firestorePatch['memory'] = patch.memory;
  if (patch.proactive !== undefined) firestorePatch['proactive'] = patch.proactive;
  if (patch.voice !== undefined) firestorePatch['voice'] = patch.voice;
  if (patch.minorScoped !== undefined) firestorePatch['minorScoped'] = patch.minorScoped;

  if (Object.keys(firestorePatch).length === 0) return;

  try {
    await updateDoc(ref, firestorePatch);
  } catch (err: unknown) {
    // Document may not yet exist — fall back to setDoc with merged defaults.
    if (
      err instanceof Error &&
      (err.message.includes('No document to update') ||
        (err as { code?: string }).code === 'not-found')
    ) {
      const initialDoc: BereanCapabilities = {
        ...SAFE_DEFAULTS,
        connectors: { ...SAFE_DEFAULTS.connectors },
        ...firestorePatch,
      } as BereanCapabilities;
      await setDoc(ref, initialDoc, { merge: true });
    } else {
      throw err;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISIBILITY PREFERENCES
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_VISIBILITY: Visibility = 'private';

/**
 * Save a per-context visibility preference.
 * Stored as `visibilityPrefs.{context}` under `berean/{uid}/capabilities/settings`.
 */
export async function saveVisibility(
  userId: string,
  context: string,
  visibility: Visibility,
): Promise<void> {
  const db = getFirestore();
  const ref = doc(db, 'berean', userId, 'capabilities', 'settings');

  const patch: Record<string, unknown> = {
    [`visibilityPrefs.${context}`]: visibility,
  };

  try {
    await updateDoc(ref, patch);
  } catch (err: unknown) {
    if (
      err instanceof Error &&
      (err.message.includes('No document to update') ||
        (err as { code?: string }).code === 'not-found')
    ) {
      // Bootstrap the document with defaults + this preference.
      await setDoc(
        ref,
        {
          ...SAFE_DEFAULTS,
          connectors: { ...SAFE_DEFAULTS.connectors },
          visibilityPrefs: { [context]: visibility },
        },
        { merge: true },
      );
    } else {
      throw err;
    }
  }
}

/**
 * Fetch the stored visibility preference for a given context.
 * Returns 'private' if no preference has been saved yet.
 */
export async function fetchVisibility(
  userId: string,
  context: string,
): Promise<Visibility> {
  const db = getFirestore();
  const ref = doc(db, 'berean', userId, 'capabilities', 'settings');
  const snap = await getDoc(ref);

  if (!snap.exists()) return DEFAULT_VISIBILITY;

  const data = snap.data() as {
    visibilityPrefs?: Record<string, Visibility>;
  };

  return data.visibilityPrefs?.[context] ?? DEFAULT_VISIBILITY;
}
