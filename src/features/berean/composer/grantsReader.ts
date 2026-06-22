/**
 * grantsReader.ts — Connector grant resolution for the Berean composer mention layer
 *
 * Agent D (@Tool Mentions) — Connected Intelligence Phase 2.
 *
 * A connector-backed mention (@calendar, @music) is available in the picker ONLY when:
 *   1. A ConnectorGrant for that connector has status === 'active'
 *   2. The grant is not expired (expiresAt === null OR expiresAt > now)
 *   3. grant.surfaces INCLUDES GrantSurface.berean
 *
 * Privacy invariant: a calendar grant scoped to scheduled_actions only (NOT berean)
 * ⇒ @calendar is ABSENT from the composer picker. Per-surface permissioning is the
 * whole point — "Calendar for reminders, not recommendations."
 *
 * Minor invariant: minor-scoped sessions ⇒ ZERO connector mentions, full stop.
 *
 * SEAM FOR AGENT A: Agent A owns the canonical grantsService. Until it lands (or to
 * override in tests), pass a `loadGrants` function to `makeGrantsReader`. The default
 * loader reads the documented Firestore path `berean/{uid}/connectorGrants/{connectorId}`.
 * When Agent A's service exists, wire it in by passing its loader here — no other change.
 *
 * OWNER: Agent D. Create-only under src/features/berean/composer/**.
 */

import { getFirestore, doc, getDoc } from 'firebase/firestore';

import {
  ConnectorId,
  GrantSurface,
  type ConnectorGrant,
} from '../../connectedIntelligence.contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Grant loader seam
// ─────────────────────────────────────────────────────────────────────────────

/** Loads all ConnectorGrant docs for a user. Returns whatever exists (possibly []). */
export type GrantLoader = (uid: string) => Promise<ConnectorGrant[]>;

/**
 * Default loader — reads `berean/{uid}/connectorGrants/{connectorId}` for the two
 * connector-backed mention sources (calendar, music). Bible + church_mgmt are aliases
 * to existing always-on adapters and do NOT require a grant doc here.
 *
 * Reads are independent and fail-soft: a missing or unreadable doc yields no grant
 * (mention simply stays absent), never an exception that breaks the picker.
 */
export const defaultGrantLoader: GrantLoader = async (uid) => {
  if (!uid) return [];
  const db = getFirestore();
  const connectorIds: ConnectorId[] = [ConnectorId.calendar, ConnectorId.music];

  const snaps = await Promise.all(
    connectorIds.map(async (connectorId) => {
      try {
        const ref = doc(db, 'berean', uid, 'connectorGrants', connectorId);
        const snap = await getDoc(ref);
        return snap.exists() ? (snap.data() as Partial<ConnectorGrant>) : null;
      } catch {
        return null;
      }
    }),
  );

  const grants: ConnectorGrant[] = [];
  snaps.forEach((data, i) => {
    if (!data) return;
    grants.push({
      uid,
      connectorId: connectorIds[i],
      scopes: Array.isArray(data.scopes) ? data.scopes : [],
      surfaces: Array.isArray(data.surfaces) ? data.surfaces : [],
      grantedAt: data.grantedAt ?? null,
      expiresAt: data.expiresAt ?? null,
      status: data.status === 'active' || data.status === 'revoked' || data.status === 'error'
        ? data.status
        : 'error',
      minorBlocked: true,
    });
  });
  return grants;
};

// ─────────────────────────────────────────────────────────────────────────────
// Availability predicate
// ─────────────────────────────────────────────────────────────────────────────

/** Coerce a Firestore Timestamp / epoch-ms / null into epoch-ms (or null). */
function toEpochMs(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === 'number') return value;
  // Firestore Timestamp at rest exposes toMillis() on the client SDK.
  const maybe = value as { toMillis?: () => number; seconds?: number };
  if (typeof maybe.toMillis === 'function') return maybe.toMillis();
  if (typeof maybe.seconds === 'number') return maybe.seconds * 1000;
  return null;
}

/**
 * A grant unlocks a Berean mention iff it is active, unexpired, and scoped to the
 * berean surface. `now` is injectable for deterministic tests.
 */
export function grantUnlocksBerean(
  grant: ConnectorGrant,
  now: number = Date.now(),
): boolean {
  if (grant.status !== 'active') return false;
  if (!grant.surfaces.includes(GrantSurface.berean)) return false;
  const expiresMs = toEpochMs(grant.expiresAt);
  if (expiresMs !== null && expiresMs <= now) return false;
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// GrantsReader
// ─────────────────────────────────────────────────────────────────────────────

export interface ConnectorAvailability {
  /** Connector-backed mentions that are available right now (berean-scoped, active). */
  available: Set<ConnectorId>;
  /** Raw active+berean grants, keyed for downstream scope inspection. */
  grantsByConnector: Map<ConnectorId, ConnectorGrant>;
}

export interface GrantsReader {
  /**
   * Resolves which connector-backed mentions are available for this user.
   * Minor-scoped ⇒ always empty (zero connector mentions).
   */
  resolve(uid: string, minorScoped: boolean): Promise<ConnectorAvailability>;
}

export function makeGrantsReader(loadGrants: GrantLoader = defaultGrantLoader): GrantsReader {
  return {
    async resolve(uid, minorScoped) {
      const empty: ConnectorAvailability = {
        available: new Set(),
        grantsByConnector: new Map(),
      };
      // Minor invariant: zero connector mentions, no reads.
      if (minorScoped) return empty;
      if (!uid) return empty;

      let grants: ConnectorGrant[];
      try {
        grants = await loadGrants(uid);
      } catch {
        // Fail-closed for connector mentions: unreadable grants ⇒ none available.
        return empty;
      }

      const now = Date.now();
      const available = new Set<ConnectorId>();
      const grantsByConnector = new Map<ConnectorId, ConnectorGrant>();

      for (const grant of grants) {
        if (grantUnlocksBerean(grant, now)) {
          available.add(grant.connectorId);
          grantsByConnector.set(grant.connectorId, grant);
        }
      }

      return { available, grantsByConnector };
    },
  };
}

export const grantsReader = makeGrantsReader();
