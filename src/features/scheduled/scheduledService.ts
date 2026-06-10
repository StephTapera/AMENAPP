/**
 * scheduledService.ts — AMEN Connected Intelligence v1, Phase 2 (Agent E)
 *
 * Firestore client persistence for ScheduledAction docs, following the Berean
 * controlsService.ts pattern (client SDK setDoc/merge, fail-soft on missing doc).
 *
 * SHIP-BLOCKER honored at the service layer: while
 * connectedIntelligence.scheduledActions.enabled === false (no Aegis review id),
 * createAction / activateAction THROW. The feature cannot be silently half-wired
 * on — a disabled feature creates no live docs.
 *
 * Collection: scheduledActions/{id}  (top-level; rules restrict execution fields
 * to server-only — see HANDOFF.md).
 *
 * Contract types imported from the FROZEN contracts; never redefined here.
 */

import {
  getFirestore,
  collection,
  doc,
  getDocs,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  query,
  where,
  serverTimestamp,
} from 'firebase/firestore';

import {
  ScheduledAction,
  ScheduleWriteRisk,
} from '../connectedIntelligence.contracts';
import { connectedIntelligence } from '../connectedIntelligence.config';
import {
  ScheduledActionPreview,
  previewToAction,
} from './scheduledTemplates';

const COLLECTION = 'scheduledActions';

// ─────────────────────────────────────────────────────────────────────────────
// GATE — single source of truth for "is this feature live?"
// ─────────────────────────────────────────────────────────────────────────────

export interface GateState {
  enabled: boolean;
  aegisReviewId: string | null;
  /** Human-readable reason the feature is gated, for the disabled UI state. */
  reason: 'pending_review' | 'live';
}

export function gateState(): GateState {
  const cfg = connectedIntelligence.scheduledActions;
  const enabled = cfg.enabled === true && cfg.aegisReviewId != null;
  return {
    enabled,
    aegisReviewId: cfg.aegisReviewId,
    reason: enabled ? 'live' : 'pending_review',
  };
}

function assertEnabled(): void {
  if (!gateState().enabled) {
    throw new Error('scheduled_actions_pending_review');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WRITE-RISK CEILING — defense in depth. Even though the enum only contains
// read_only + drafts_for_approval, we assert it explicitly so any future drift
// fails closed rather than silently permitting an autonomous external write.
// ─────────────────────────────────────────────────────────────────────────────

const ALLOWED_WRITE_RISKS: ReadonlySet<ScheduleWriteRisk> = new Set([
  ScheduleWriteRisk.read_only,
  ScheduleWriteRisk.drafts_for_approval,
]);

function assertWriteRiskCeiling(risk: ScheduleWriteRisk): void {
  if (!ALLOWED_WRITE_RISKS.has(risk)) {
    throw new Error('write_risk_ceiling_exceeded');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAP — active actions per plan. Free vs Plus from config.
// ─────────────────────────────────────────────────────────────────────────────

function maxActiveFor(plan: 'free' | 'plus' | 'pro'): number {
  const cfg = connectedIntelligence.scheduledActions;
  return plan === 'free' ? cfg.maxActiveFree : cfg.maxActivePlus;
}

// ─────────────────────────────────────────────────────────────────────────────
// READ
// ─────────────────────────────────────────────────────────────────────────────

export async function listActions(uid: string): Promise<ScheduledAction[]> {
  const db = getFirestore();
  const q = query(collection(db, COLLECTION), where('uid', '==', uid));
  const snap = await getDocs(q);
  return snap.docs
    .map((d) => ({ id: d.id, ...(d.data() as Omit<ScheduledAction, 'id'>) }))
    .filter((a) => a.status !== 'deleted');
}

export async function getAction(id: string): Promise<ScheduledAction | null> {
  const db = getFirestore();
  const snap = await getDoc(doc(db, COLLECTION, id));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<ScheduledAction, 'id'>) };
}

/** Count toward the active cap: live + dry_run, but not paused/deleted. */
function countsTowardCap(a: ScheduledAction): boolean {
  return a.status === 'active' || a.status === 'dry_run';
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATE — from a confirmed preview. Starts dryRun=true / status='dry_run'.
// ─────────────────────────────────────────────────────────────────────────────

export interface CreateResult {
  id: string;
  action: ScheduledAction;
}

export async function createAction(
  uid: string,
  plan: 'free' | 'plus' | 'pro',
  preview: ScheduledActionPreview,
): Promise<CreateResult> {
  assertEnabled();
  assertWriteRiskCeiling(preview.writeRisk);

  // Cap enforcement (client-side; server rules enforce again).
  const existing = await listActions(uid);
  const active = existing.filter(countsTowardCap).length;
  if (active >= maxActiveFor(plan)) {
    throw new Error('active_actions_cap_reached');
  }

  const { aegisReviewId } = gateState();
  const base = previewToAction(preview, uid, aegisReviewId);

  const db = getFirestore();
  const ref = doc(collection(db, COLLECTION));
  // Server-managed execution fields are initialized to safe values; Firestore
  // rules forbid the client from ever writing the run-result fields after this.
  await setDoc(ref, {
    ...base,
    templateId: preview.templateId,
    requiresConsent: preview.requiresConsent,
    consentGranted: preview.requiresConsent ? false : true,
    sabbathOverrideLocked: preview.sabbathOverrideLocked,
    dryRunsCompleted: 0,
    lastRunAt: null,
    lastRunStatus: null,      // 'ok' | 'dry_run' | 'failed' — written by server only
    lastRunFailureReason: null,
    createdAt: serverTimestamp(),
  });

  const action = (await getAction(ref.id))!;
  return { id: ref.id, action };
}

// ─────────────────────────────────────────────────────────────────────────────
// LIFECYCLE — pause / resume / promote-to-live / consent / delete
// ─────────────────────────────────────────────────────────────────────────────

export async function pauseAction(id: string): Promise<void> {
  assertEnabled();
  const db = getFirestore();
  await updateDoc(doc(db, COLLECTION, id), { status: 'paused' });
}

export async function resumeAction(id: string): Promise<void> {
  assertEnabled();
  const action = await getAction(id);
  if (!action) throw new Error('not_found');
  // Resuming returns to dry_run if dry-runs are not yet exhausted, else active.
  const db = getFirestore();
  await updateDoc(doc(db, COLLECTION, id), {
    status: action.dryRun ? 'dry_run' : 'active',
  });
}

/**
 * Promote a dry-run action to live. Explicit user choice only — never automatic.
 * Refuses if consent is required but not granted.
 */
export async function promoteToLive(id: string): Promise<void> {
  assertEnabled();
  const action = await getAction(id);
  if (!action) throw new Error('not_found');

  const db = getFirestore();
  const snap = await getDoc(doc(db, COLLECTION, id));
  const data = snap.data() as { requiresConsent?: boolean; consentGranted?: boolean };
  if (data?.requiresConsent && !data?.consentGranted) {
    throw new Error('consent_required');
  }

  await updateDoc(doc(db, COLLECTION, id), {
    dryRun: false,
    status: 'active',
  });
}

export async function grantConsent(id: string): Promise<void> {
  assertEnabled();
  const db = getFirestore();
  await updateDoc(doc(db, COLLECTION, id), { consentGranted: true });
}

/** Soft delete: status='deleted'. Hard purge is a server retention job. */
export async function deleteAction(id: string): Promise<void> {
  const db = getFirestore();
  await updateDoc(doc(db, COLLECTION, id), { status: 'deleted' });
}

/** Hard delete — used only for never-activated previews abandoned at creation. */
export async function hardDeleteAction(id: string): Promise<void> {
  const db = getFirestore();
  await deleteDoc(doc(db, COLLECTION, id));
}

/**
 * Toggle Sabbath suppression. Refuses when the template locks the override on
 * (digest spam guard / care template).
 */
export async function setSabbathSuppressed(
  id: string,
  suppressed: boolean,
): Promise<void> {
  assertEnabled();
  const db = getFirestore();
  const snap = await getDoc(doc(db, COLLECTION, id));
  const data = snap.data() as { sabbathOverrideLocked?: boolean };
  if (data?.sabbathOverrideLocked && suppressed === false) {
    throw new Error('sabbath_override_locked');
  }
  await updateDoc(doc(db, COLLECTION, id), { sabbathSuppressed: suppressed });
}
