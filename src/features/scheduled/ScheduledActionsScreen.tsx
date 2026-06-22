/**
 * ScheduledActionsScreen.tsx — AMEN Connected Intelligence v1, Phase 2 (Agent E)
 *
 * The Scheduled Actions surface. Liquid Glass white/light.
 *
 * SHIP-BLOCKER honored: when the feature is gated OFF (no Aegis review id), the
 * screen renders a clear "pending capability review" state — NOT dead buttons,
 * NOT a fake-working flow. No create/list/persist paths are reachable in that state.
 *
 * Distinct UI states (all real, no stubs):
 *   1. DISABLED      — pending capability review (Aegis gate not satisfied)
 *   2. LOADING       — fetching the user's actions
 *   3. ERROR         — fetch failed, with retry
 *   4. EMPTY         — enabled, zero actions, invites first creation
 *   5. LIST          — one or more actions
 *   6. CREATE        — NL → parsed preview → confirm sheet
 * Plus, per item, two more rendered states:
 *   • DRY-RUN "would have" card (first N runs)
 *   • RUN-FAILED strip (never silent, never fabricated)
 *
 * FORBIDDEN: gold, purple, cosmic-dark, Cormorant Garamond.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { tokens } from '../../berean/contracts';
import { connectedIntelligence } from '../connectedIntelligence.config';
import {
  ScheduledAction,
  ScheduleWriteRisk,
  ScheduleKind,
} from '../connectedIntelligence.contracts';
import { s } from './scheduledStyles';
import {
  gateState,
  listActions,
  createAction,
  pauseAction,
  resumeAction,
  promoteToLive,
  deleteAction,
  grantConsent,
  setSabbathSuppressed,
} from './scheduledService';
import {
  TEMPLATES,
  TemplateDef,
  ScheduledActionPreview,
  parseNaturalLanguage,
} from './scheduledTemplates';

// Server-augmented shape we read back from Firestore (execution fields are
// server-written; the screen only displays them).
type ActionDoc = ScheduledAction & {
  templateId?: string;
  requiresConsent?: boolean;
  consentGranted?: boolean;
  sabbathOverrideLocked?: boolean;
  dryRunsCompleted?: number;
  lastRunStatus?: 'ok' | 'dry_run' | 'failed' | 'sabbath_skip' | 'consent_pending' | null;
  lastRunFailureReason?: string | null;
  lastRunPreviewText?: string | null; // "would have sent…" text written by server in dry-run
};

interface Props {
  userId: string;
  plan?: 'free' | 'plus' | 'pro';
}

type ViewState = 'loading' | 'error' | 'ready';

// ─────────────────────────────────────────────────────────────────────────────
// Small presentational helpers
// ─────────────────────────────────────────────────────────────────────────────

function Pill({
  children,
  variant = 'default',
}: {
  children: React.ReactNode;
  variant?: 'default' | 'accent' | 'warn' | 'care';
}) {
  const extra =
    variant === 'accent'
      ? s.pillAccent
      : variant === 'warn'
        ? s.pillWarn
        : variant === 'care'
          ? s.pillCare
          : {};
  return <span style={{ ...s.pill, ...extra }}>{children}</span>;
}

function writeRiskLabel(r: ScheduleWriteRisk): string {
  return r === ScheduleWriteRisk.read_only ? 'Read-only' : 'Drafts for approval';
}

function kindLabel(k: ScheduleKind): string {
  return k === ScheduleKind.reminder
    ? 'Reminder'
    : k === ScheduleKind.digest
      ? 'Digest'
      : 'Follow-up';
}

// ─────────────────────────────────────────────────────────────────────────────
// DISABLED / pending-review state
// ─────────────────────────────────────────────────────────────────────────────

function PendingReviewState() {
  return (
    <div style={s.screen}>
      <div style={s.header}>
        <h1 style={s.pageTitle}>Scheduled Actions</h1>
        <p style={s.pageSub}>
          Let Berean quietly handle gentle, recurring routines for you.
        </p>
      </div>

      <div style={s.pendingBanner}>
        <p style={s.pendingTitle}>Pending capability review</p>
        <p style={s.pendingBody}>
          Scheduled Actions is being reviewed by our safety team before it goes
          live. Recurring routines can touch a lot of people, so we hold them to a
          higher bar: every action drafts for your approval first, and nothing is
          ever sent on your behalf without you. We’ll turn this on here as soon as
          the review is complete.
        </p>
        <div style={{ marginTop: 14 }}>
          <Pill variant="accent">Safety review in progress</Pill>
        </div>
      </div>

      <div style={s.section}>
        <p style={s.sectionTitle}>What it will do</p>
        <div style={s.card}>
          {TEMPLATES.map((t, i) => (
            <div
              key={t.id}
              style={{ ...s.pad, ...(i > 0 ? s.rowDivider : {}) }}
            >
              <p style={s.itemTitle}>{t.title}</p>
              <p style={s.itemSub}>{t.blurb}</p>
            </div>
          ))}
        </div>
        <p
          style={{
            fontSize: 12,
            color: tokens.textSub,
            margin: '12px 4px 0 4px',
            lineHeight: 1.5,
          }}
        >
          Previewed, not active. These cards describe what Scheduled Actions will
          offer once the review clears — none of them are running.
        </p>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATE sheet — NL → preview → confirm
// ─────────────────────────────────────────────────────────────────────────────

function CreateSheet({
  userId,
  plan,
  onClose,
  onCreated,
}: {
  userId: string;
  plan: 'free' | 'plus' | 'pro';
  onClose: () => void;
  onCreated: () => void;
}) {
  const [text, setText] = useState('');
  const [preview, setPreview] = useState<ScheduledActionPreview | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [consentChecked, setConsentChecked] = useState(false);

  const selectTemplate = (t: TemplateDef) => {
    setError(null);
    setPreview(t.build());
    setConsentChecked(false);
  };

  const parse = () => {
    setError(null);
    setPreview(parseNaturalLanguage(text));
    setConsentChecked(false);
  };

  const confirm = useCallback(async () => {
    if (!preview) return;
    if (preview.requiresConsent && !consentChecked) {
      setError('Please confirm consent to continue.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await createAction(userId, plan, preview);
      // If consent was confirmed inline, record it on the new doc.
      if (preview.requiresConsent && consentChecked) {
        await grantConsent(res.id);
      }
      onCreated();
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'unknown';
      setError(friendlyError(msg));
      setBusy(false);
    }
  }, [preview, consentChecked, userId, plan, onCreated]);

  return (
    <div style={s.modalScrim} onClick={onClose}>
      <div style={s.sheet} onClick={(e) => e.stopPropagation()}>
        <div style={s.header}>
          <h1 style={s.pageTitle}>New scheduled action</h1>
          <p style={s.pageSub}>
            Describe it in your own words, or pick a starting point. You’ll see
            exactly what it does before anything is saved.
          </p>
        </div>

        {/* NL input */}
        <div style={s.section}>
          <p style={s.sectionTitle}>Describe it</p>
          <div style={s.card}>
            <div style={s.pad}>
              <textarea
                style={s.input}
                rows={2}
                placeholder='e.g. "Remind me to pray every morning"'
                value={text}
                onChange={(e) => setText(e.target.value)}
                aria-label="Describe your scheduled action"
              />
              <div style={{ marginTop: 10, textAlign: 'right' }}>
                <button style={s.secondaryBtn} onClick={parse}>
                  Preview
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Templates */}
        <div style={s.section}>
          <p style={s.sectionTitle}>Or start from a template</p>
          <div style={s.card}>
            {TEMPLATES.map((t, i) => (
              <div
                key={t.id}
                role="button"
                tabIndex={0}
                style={{ ...s.templateRow, ...(i > 0 ? s.rowDivider : {}) }}
                onClick={() => selectTemplate(t)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    selectTemplate(t);
                  }
                }}
              >
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={s.itemTitle}>{t.title}</p>
                  <p style={s.itemSub}>{t.blurb}</p>
                </div>
                <span style={{ color: tokens.accent, fontSize: 22, lineHeight: 1 }}>
                  ›
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* PREVIEW — the confirmation gate */}
        {preview && (
          <div style={s.section}>
            <p style={s.sectionTitle}>Preview — confirm before saving</p>
            <div style={s.card}>
              <div style={s.pad}>
                <p style={s.itemTitle}>{preview.humanReadable}</p>
                <p style={s.itemSub}>{preview.blurb}</p>
                <div
                  style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}
                >
                  <Pill variant="default">{kindLabel(preview.kind)}</Pill>
                  <Pill
                    variant={
                      preview.writeRisk === ScheduleWriteRisk.read_only
                        ? 'default'
                        : 'accent'
                    }
                  >
                    {writeRiskLabel(preview.writeRisk)}
                  </Pill>
                  <Pill variant="accent">Starts in dry-run</Pill>
                  {preview.sabbathSuppressed && (
                    <Pill variant="default">Sabbath-suppressed</Pill>
                  )}
                  {preview.requiresConsent && <Pill variant="care">Care · consent</Pill>}
                </div>

                <div
                  style={{
                    marginTop: 12,
                    fontSize: 13,
                    color: tokens.textSub,
                    lineHeight: 1.5,
                  }}
                >
                  {preview.prompt}
                </div>

                {/* Dry-run explainer */}
                <div style={s.dryRunCard}>
                  <p style={s.dryRunLabel}>Dry-run first</p>
                  <p style={{ ...s.itemSub, marginTop: 0 }}>
                    Its first {connectedIntelligence.scheduledActions.dryRunCount}{' '}
                    runs only show you “here’s what I would have done” — nothing is
                    sent or created. You promote it to live yourself when you’re
                    ready.
                  </p>
                </div>

                {/* Care consent gate */}
                {preview.requiresConsent && (
                  <label
                    style={{
                      display: 'flex',
                      alignItems: 'flex-start',
                      gap: 10,
                      marginTop: 14,
                      cursor: 'pointer',
                    }}
                  >
                    <input
                      type="checkbox"
                      checked={consentChecked}
                      onChange={(e) => setConsentChecked(e.target.checked)}
                      aria-label="Confirm consent for care follow-up"
                      style={{ marginTop: 3 }}
                    />
                    <span style={{ ...s.itemSub, marginTop: 0 }}>
                      I confirm this only nudges a circle leader about requests the
                      requester has chosen to share. It’s private care — never a
                      public list, never counts, never shaming.
                    </span>
                  </label>
                )}

                {error && <p style={s.errorText}>{error}</p>}

                <div
                  style={{
                    display: 'flex',
                    gap: 10,
                    marginTop: 16,
                    justifyContent: 'flex-end',
                  }}
                >
                  <button style={s.secondaryBtn} onClick={onClose} disabled={busy}>
                    Cancel
                  </button>
                  <button style={s.primaryBtn} onClick={confirm} disabled={busy}>
                    {busy ? 'Saving…' : 'Save in dry-run'}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {!preview && (
          <div style={{ textAlign: 'center', padding: '16px 0 4px' }}>
            <button style={s.ghostBtn} onClick={onClose}>
              Cancel
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION CARD — list item with per-state rendering (dry-run, live, paused, failed)
// ─────────────────────────────────────────────────────────────────────────────

function ActionCard({
  action,
  onChanged,
}: {
  action: ActionDoc;
  onChanged: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      onChanged();
    } catch (e) {
      setError(friendlyError(e instanceof Error ? e.message : 'unknown'));
      setBusy(false);
    }
  };

  const dryRunsLeft = Math.max(
    0,
    connectedIntelligence.scheduledActions.dryRunCount -
      (action.dryRunsCompleted ?? 0),
  );
  const isDryRun = action.status === 'dry_run';
  const isPaused = action.status === 'paused';
  const isLive = action.status === 'active';
  const failed = action.lastRunStatus === 'failed';
  const pendingConsent = action.requiresConsent && !action.consentGranted;

  return (
    <div style={{ ...s.card, marginBottom: 12 }}>
      <div style={s.pad}>
        <div
          style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}
        >
          <div style={{ flex: 1, minWidth: 0 }}>
            <p style={s.itemTitle}>{action.humanReadable}</p>
            <p style={s.itemSub}>{action.prompt}</p>
          </div>
        </div>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}>
          <Pill>{kindLabel(action.kind)}</Pill>
          <Pill variant={action.writeRisk === ScheduleWriteRisk.read_only ? 'default' : 'accent'}>
            {writeRiskLabel(action.writeRisk)}
          </Pill>
          {isLive && <Pill variant="accent">Live</Pill>}
          {isPaused && <Pill>Paused</Pill>}
          {isDryRun && <Pill variant="accent">Dry-run · {dryRunsLeft} left</Pill>}
          {action.sabbathSuppressed && <Pill>Rests on Sabbath</Pill>}
          {action.requiresConsent && <Pill variant="care">Care</Pill>}
        </div>

        {/* RUN-FAILED strip — never silent, never a fabricated result */}
        {failed && (
          <div style={s.failedStrip}>
            <p style={s.failedLabel}>Last run failed</p>
            <p style={{ ...s.itemSub, marginTop: 0 }}>
              The most recent run didn’t complete
              {action.lastRunFailureReason
                ? `: ${action.lastRunFailureReason}.`
                : '.'}{' '}
              Nothing was sent or drafted. We’ll try again on the next schedule.
            </p>
          </div>
        )}

        {/* DRY-RUN "would have" preview card */}
        {isDryRun && action.lastRunStatus === 'dry_run' && (
          <div style={s.dryRunCard}>
            <p style={s.dryRunLabel}>Here’s what I would have done</p>
            <p style={{ ...s.itemSub, marginTop: 0 }}>
              {action.lastRunPreviewText ||
                'Your last scheduled run produced a preview only — nothing was sent or created.'}
            </p>
          </div>
        )}

        {/* Consent still pending */}
        {pendingConsent && (
          <div style={{ ...s.dryRunCard, borderStyle: 'solid' }}>
            <p style={s.dryRunLabel}>Consent needed</p>
            <p style={{ ...s.itemSub, marginTop: 0 }}>
              This care action stays paused until you confirm consent.
            </p>
            <button
              style={{ ...s.ghostBtn, marginTop: 6 }}
              disabled={busy}
              onClick={() => run(() => grantConsent(action.id))}
            >
              Confirm consent
            </button>
          </div>
        )}

        {error && <p style={s.errorText}>{error}</p>}

        {/* Controls */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            marginTop: 14,
            flexWrap: 'wrap',
          }}
        >
          {isDryRun && !pendingConsent && (
            <button
              style={s.primaryBtn}
              disabled={busy}
              onClick={() => run(() => promoteToLive(action.id))}
            >
              Promote to live
            </button>
          )}
          {isLive && (
            <button
              style={s.secondaryBtn}
              disabled={busy}
              onClick={() => run(() => pauseAction(action.id))}
            >
              Pause
            </button>
          )}
          {isPaused && (
            <button
              style={s.secondaryBtn}
              disabled={busy}
              onClick={() => run(() => resumeAction(action.id))}
            >
              Resume
            </button>
          )}
          {!action.sabbathOverrideLocked && (
            <button
              style={s.ghostBtn}
              disabled={busy}
              onClick={() =>
                run(() =>
                  setSabbathSuppressed(action.id, !action.sabbathSuppressed),
                )
              }
            >
              {action.sabbathSuppressed ? 'Allow on Sabbath' : 'Rest on Sabbath'}
            </button>
          )}
          <div style={{ flex: 1 }} />
          <button
            style={s.dangerGhostBtn}
            disabled={busy}
            onClick={() => run(() => deleteAction(action.id))}
          >
            Delete
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

export function ScheduledActionsScreen({ userId, plan = 'free' }: Props) {
  const gate = gateState();

  const [view, setView] = useState<ViewState>('loading');
  const [actions, setActions] = useState<ActionDoc[]>([]);
  const [creating, setCreating] = useState(false);

  const reload = useCallback(async () => {
    setView('loading');
    try {
      const list = (await listActions(userId)) as ActionDoc[];
      setActions(list);
      setView('ready');
    } catch {
      setView('error');
    }
  }, [userId]);

  useEffect(() => {
    if (gate.enabled) reload();
  }, [gate.enabled, reload]);

  // STATE 1 — DISABLED / pending capability review (SHIP-BLOCKER).
  if (!gate.enabled) return <PendingReviewState />;

  // STATE 2 — LOADING.
  if (view === 'loading') {
    return (
      <div style={s.screen}>
        <div style={s.header}>
          <h1 style={s.pageTitle}>Scheduled Actions</h1>
        </div>
        <div style={s.spinnerWrap}>Loading your scheduled actions…</div>
      </div>
    );
  }

  // STATE 3 — ERROR.
  if (view === 'error') {
    return (
      <div style={s.screen}>
        <div style={s.header}>
          <h1 style={s.pageTitle}>Scheduled Actions</h1>
        </div>
        <div style={s.emptyWrap}>
          <p style={s.emptyTitle}>We couldn’t load your actions</p>
          <p style={{ fontSize: 14, lineHeight: 1.5 }}>
            Something went wrong reaching your scheduled actions. Your data is
            safe.
          </p>
          <div style={{ marginTop: 16 }}>
            <button style={s.primaryBtn} onClick={reload}>
              Try again
            </button>
          </div>
        </div>
      </div>
    );
  }

  // STATES 4 + 5 — READY (empty vs list).
  return (
    <div style={s.screen}>
      <div style={s.header}>
        <h1 style={s.pageTitle}>Scheduled Actions</h1>
        <p style={s.pageSub}>
          Gentle, recurring routines. Each one drafts for your approval — nothing
          is ever sent on your behalf without you.
        </p>
      </div>

      {actions.length === 0 ? (
        // STATE 4 — EMPTY.
        <div style={s.emptyWrap}>
          <div style={{ fontSize: 40 }} aria-hidden>
            🕊️
          </div>
          <p style={s.emptyTitle}>No scheduled actions yet</p>
          <p style={{ fontSize: 14, lineHeight: 1.5, maxWidth: 340, margin: '0 auto' }}>
            Set up a gentle routine — a daily prayer nudge, a weekly reading plan,
            or a Friday group digest. Everything starts in dry-run so you see it
            work before it’s live.
          </p>
          <div style={{ marginTop: 20 }}>
            <button style={s.primaryBtn} onClick={() => setCreating(true)}>
              Create your first
            </button>
          </div>
        </div>
      ) : (
        // STATE 5 — LIST.
        <>
          <div style={{ ...s.section, marginTop: 8 }}>
            <button
              style={{ ...s.primaryBtn, width: '100%' }}
              onClick={() => setCreating(true)}
            >
              New scheduled action
            </button>
          </div>
          <div style={s.section}>
            {actions.map((a) => (
              <ActionCard key={a.id} action={a} onChanged={reload} />
            ))}
          </div>
        </>
      )}

      {/* STATE 6 — CREATE. */}
      {creating && (
        <CreateSheet
          userId={userId}
          plan={plan}
          onClose={() => setCreating(false)}
          onCreated={() => {
            setCreating(false);
            reload();
          }}
        />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Error copy mapping — service throws are turned into human sentences.
// ─────────────────────────────────────────────────────────────────────────────

function friendlyError(code: string): string {
  switch (code) {
    case 'scheduled_actions_pending_review':
      return 'Scheduled Actions is still under safety review and can’t be used yet.';
    case 'active_actions_cap_reached':
      return 'You’ve reached the limit of active actions for your plan. Pause or delete one to add another.';
    case 'consent_required':
      return 'This care action needs your consent before it can go live.';
    case 'sabbath_override_locked':
      return 'This action always rests on the Sabbath and can’t be overridden.';
    case 'write_risk_ceiling_exceeded':
      return 'That action isn’t allowed — scheduled actions can only draft for approval, never send on their own.';
    default:
      return 'Something went wrong. Please try again.';
  }
}

export default ScheduledActionsScreen;
