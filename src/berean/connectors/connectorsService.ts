/**
 * connectorsService.ts — Berean connector state management
 * Phase 2D: Berean Connectors
 *
 * Reads/writes connector state to Firestore at berean/{uid}/connectors/{type}.
 * Faith-native connectors ONLY: bible | church_calendar | giving | sermon_library.
 * Generic productivity connectors (Notion, Google Drive, Slack, etc.) are NOT supported.
 */

import {
  getFirestore,
  doc,
  getDoc,
  setDoc,
  serverTimestamp,
} from 'firebase/firestore';
import type { ConnectorType } from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────────────────────

export interface ConnectorState {
  bible: boolean;
  church_calendar: boolean;
  giving: boolean;
  sermon_library: boolean;
}

const SUPPORTED_CONNECTOR_TYPES: ConnectorType[] = [
  'bible',
  'church_calendar',
  'giving',
  'sermon_library',
];

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

function assertSupportedType(type: ConnectorType): void {
  if (!(SUPPORTED_CONNECTOR_TYPES as string[]).includes(type)) {
    throw new Error('unsupported_connector_type');
  }
}

function assertNotMinor(minorScoped: boolean): void {
  if (minorScoped) {
    throw new Error('connectors_blocked_minor');
  }
}

function connectorDocRef(userId: string, type: ConnectorType) {
  const db = getFirestore();
  return doc(db, 'berean', userId, 'connectors', type);
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetches the connector state for all four faith-native connector types.
 * A connector is considered active if its Firestore document has status === 'active'.
 *
 * Minor guard: pass minorScoped from the user's token claim. If true, throws
 * 'connectors_blocked_minor' — callers should catch and show the minor banner.
 */
export async function fetchConnectors(
  userId: string,
  minorScoped = false
): Promise<ConnectorState> {
  assertNotMinor(minorScoped);

  const db = getFirestore();
  const types: ConnectorType[] = ['bible', 'church_calendar', 'giving', 'sermon_library'];

  const snapshots = await Promise.all(
    types.map((type) => getDoc(doc(db, 'berean', userId, 'connectors', type)))
  );

  const [bibleSnap, calendarSnap, givingSnap, sermonSnap] = snapshots;

  return {
    bible: bibleSnap.exists() && bibleSnap.data()?.['status'] === 'active',
    church_calendar: calendarSnap.exists() && calendarSnap.data()?.['status'] === 'active',
    giving: givingSnap.exists() && givingSnap.data()?.['status'] === 'active',
    sermon_library: sermonSnap.exists() && sermonSnap.data()?.['status'] === 'active',
  };
}

/**
 * Activates a connector for the given user.
 *
 * Minor guard: if minorScoped is true, throws 'connectors_blocked_minor'.
 * Type guard: if type is not a supported faith-native connector, throws 'unsupported_connector_type'.
 */
export async function connectConnector(
  userId: string,
  type: ConnectorType,
  minorScoped = false
): Promise<void> {
  assertNotMinor(minorScoped);
  assertSupportedType(type);

  await setDoc(
    connectorDocRef(userId, type),
    {
      type,
      status: 'active',
      providerId: type,
      scopes: [],
      connectedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Revokes a connector for the given user.
 *
 * Minor guard: if minorScoped is true, throws 'connectors_blocked_minor'.
 * Type guard: if type is not a supported faith-native connector, throws 'unsupported_connector_type'.
 * Uses 'revoked' status (soft revoke) — document is kept for audit purposes.
 */
export async function revokeConnector(
  userId: string,
  type: ConnectorType,
  minorScoped = false
): Promise<void> {
  assertNotMinor(minorScoped);
  assertSupportedType(type);

  await setDoc(
    connectorDocRef(userId, type),
    {
      type,
      status: 'revoked',
    },
    { merge: true }
  );
}
