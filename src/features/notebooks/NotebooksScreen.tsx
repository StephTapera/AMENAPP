/**
 * NotebooksScreen.tsx — Amen Notebooks (Connected Intelligence v1)
 *
 * White/light Apple-native Liquid Glass. All tokens imported from
 * berean/contracts.ts. FORBIDDEN: cosmic-dark, gold, purple, Cormorant Garamond.
 *
 * Renders ALL SIX UI states + the explicit ungrounded-REFUSE state:
 *   1. LOADING      — fetching the notebook list
 *   2. EMPTY        — no notebooks yet (create affordance)
 *   3. LIST         — notebooks grid + create
 *   4. DETAIL       — a notebook: its sources + grounded query UX
 *   5. ANSWER       — grounded answer with per-chunk citations
 *   6. ERROR        — infrastructure / network failure (retry)
 *   + REFUSE        — explicit ungrounded refusal with an "add sources" affordance
 *                     (visually distinct from ERROR — calm, not alarming)
 *
 * Every button is wired to a real Cloud Function via notebooksService — no stubs.
 */

import React, { useEffect, useState, useCallback } from 'react';
import { tokens } from '../../berean/contracts';
import type { Notebook, NotebookKind } from '../connectedIntelligence.contracts';
import {
  listNotebooks,
  createNotebook,
  ingestSource,
  queryNotebook,
  softDeleteNotebook,
  SUGGESTED_PROMPTS,
  type NotebookQueryResult,
  type NotebookGroundedAnswer,
} from './notebooksService';

// ─────────────────────────────────────────────────────────────────────────────
// PROPS
// ─────────────────────────────────────────────────────────────────────────────

interface NotebooksScreenProps {
  userId: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// KIND METADATA
// ─────────────────────────────────────────────────────────────────────────────

const KIND_META: Record<NotebookKind, { icon: string; label: string }> = {
  sermon: { icon: '🎙', label: 'Sermon' },
  study: { icon: '📖', label: 'Study' },
  prayer_journal: { icon: '🙏', label: 'Prayer Journal' },
  project: { icon: '🗂', label: 'Project' },
  group: { icon: '👥', label: 'Group' },
  event: { icon: '📅', label: 'Event' },
};

const KINDS = Object.keys(KIND_META) as NotebookKind[];

// ─────────────────────────────────────────────────────────────────────────────
// STYLES — Liquid Glass white/light
// ─────────────────────────────────────────────────────────────────────────────

const FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif';

const S = {
  screen: {
    backgroundColor: tokens.bg,
    minHeight: '100vh',
    fontFamily: FONT,
    padding: '24px 16px 48px',
    boxSizing: 'border-box' as const,
    color: tokens.text,
  },
  heading: { fontSize: 24, fontWeight: 700, letterSpacing: -0.4, marginBottom: 4 },
  subheading: { fontSize: 14, color: tokens.textSub, marginBottom: 22 },
  card: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '18px 16px',
  },
  cardList: { display: 'flex', flexDirection: 'column' as const, gap: 14 },
  nbRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    cursor: 'pointer',
    width: '100%',
    textAlign: 'left' as const,
    background: 'transparent',
    border: 'none',
    fontFamily: 'inherit',
  },
  nbIcon: { fontSize: 26, lineHeight: 1, flexShrink: 0 },
  nbTitle: { fontSize: 16, fontWeight: 600, color: tokens.text },
  nbMeta: { fontSize: 12, color: tokens.textSub, marginTop: 2 },
  primaryBtn: (disabled = false): React.CSSProperties => ({
    backgroundColor: disabled ? '#E5E5EA' : tokens.accent,
    color: disabled ? '#AEAEB2' : '#FFFFFF',
    border: 'none',
    borderRadius: 12,
    padding: '11px 22px',
    fontSize: 15,
    fontWeight: 600,
    cursor: disabled ? 'not-allowed' : 'pointer',
    fontFamily: 'inherit',
    opacity: disabled ? 0.6 : 1,
  }),
  ghostBtn: {
    background: 'transparent',
    color: tokens.accent,
    border: 'none',
    borderRadius: 10,
    padding: '8px 12px',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
  } as React.CSSProperties,
  destructiveBtn: {
    background: 'transparent',
    color: '#FF3B30',
    border: 'none',
    fontSize: 13,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
  } as React.CSSProperties,
  input: {
    width: '100%',
    boxSizing: 'border-box' as const,
    border: `1px solid ${tokens.divider}`,
    borderRadius: 12,
    padding: '11px 14px',
    fontSize: 15,
    fontFamily: 'inherit',
    color: tokens.text,
    backgroundColor: '#FFFFFF',
    outline: 'none',
  },
  textarea: {
    width: '100%',
    boxSizing: 'border-box' as const,
    border: `1px solid ${tokens.divider}`,
    borderRadius: 12,
    padding: '11px 14px',
    fontSize: 15,
    fontFamily: 'inherit',
    color: tokens.text,
    backgroundColor: '#FFFFFF',
    minHeight: 90,
    resize: 'vertical' as const,
    outline: 'none',
  },
  pill: (active: boolean): React.CSSProperties => ({
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
    padding: '8px 14px',
    borderRadius: 999,
    border: `1px solid ${active ? tokens.accent : tokens.divider}`,
    backgroundColor: active ? 'rgba(0,122,255,0.08)' : '#FFFFFF',
    color: active ? tokens.accent : tokens.text,
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'inherit',
  }),
  suggestPill: {
    display: 'inline-flex',
    padding: '7px 13px',
    borderRadius: 999,
    border: `1px solid ${tokens.divider}`,
    backgroundColor: '#FFFFFF',
    color: tokens.text,
    fontSize: 13,
    fontWeight: 500,
    cursor: 'pointer',
    fontFamily: 'inherit',
  } as React.CSSProperties,
  sectionLabel: {
    fontSize: 12,
    fontWeight: 600,
    color: tokens.textSub,
    textTransform: 'uppercase' as const,
    letterSpacing: 0.4,
    marginBottom: 8,
  },
  divider: { height: 1, backgroundColor: tokens.divider, border: 'none', margin: '18px 0' },
  // REFUSE state — calm, distinct from error (blue-tinted, not red).
  refuseCard: {
    backgroundColor: '#F2F7FF',
    border: `1px solid rgba(0,122,255,0.25)`,
    borderRadius: tokens.radius,
    padding: '18px 16px',
  },
  // ERROR state — alarming, red-tinted.
  errorCard: {
    backgroundColor: '#FFF5F5',
    border: '1px solid rgba(255,59,48,0.3)',
    borderRadius: tokens.radius,
    padding: '18px 16px',
  },
  answerCard: {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: '18px 16px',
    whiteSpace: 'pre-wrap' as const,
    fontSize: 15,
    lineHeight: 1.55,
    color: tokens.text,
  },
  citation: {
    display: 'block',
    border: `1px solid ${tokens.divider}`,
    borderRadius: 12,
    padding: '10px 12px',
    marginTop: 8,
    backgroundColor: '#FAFAF9',
    fontSize: 13,
    color: tokens.textSub,
    textDecoration: 'none',
  },
  centered: { textAlign: 'center' as const, color: tokens.textSub, fontSize: 14, marginTop: 48 },
  spinner: { textAlign: 'center' as const, color: tokens.textSub, fontSize: 14, marginTop: 48 },
};

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

function Citations({ answer }: { answer: NotebookGroundedAnswer }): JSX.Element {
  return (
    <div style={{ marginTop: 14 }}>
      <div style={S.sectionLabel}>
        Sources used {answer.scripture ? '(notebook + scripture)' : ''}
      </div>
      {answer.citations.map((c, i) => {
        const body = (
          <>
            <strong style={{ color: tokens.text }}>{c.marker}</strong>{' '}
            {c.sourceTitle || c.sourceType || 'Source'}
            {typeof c.score === 'number' ? ` · ${(c.score * 100).toFixed(0)}% match` : ''}
            <div style={{ marginTop: 4 }}>{c.snippet}…</div>
          </>
        );
        return c.pointer ? (
          <a
            key={i}
            href={c.pointer}
            style={S.citation}
            aria-label={`Open source ${c.marker}`}
          >
            {body}
          </a>
        ) : (
          <div key={i} style={S.citation}>
            {body}
          </div>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATE NOTEBOOK FORM
// ─────────────────────────────────────────────────────────────────────────────

function CreateNotebook({
  onCreated,
  onCancel,
}: {
  onCreated: () => void;
  onCancel: () => void;
}): JSX.Element {
  const [kind, setKind] = useState<NotebookKind>('sermon');
  const [title, setTitle] = useState('');
  const [spaceId, setSpaceId] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    if (busy || title.trim() === '') return;
    setBusy(true);
    setError(null);
    try {
      await createNotebook({
        kind,
        title: title.trim(),
        sharedWithSpaceId: kind === 'group' && spaceId.trim() ? spaceId.trim() : null,
      });
      onCreated();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create notebook.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={S.card}>
      <div style={S.sectionLabel}>New notebook</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginBottom: 14 }}>
        {KINDS.map((k) => (
          <button key={k} style={S.pill(kind === k)} onClick={() => setKind(k)} aria-pressed={kind === k}>
            <span aria-hidden="true">{KIND_META[k].icon}</span> {KIND_META[k].label}
          </button>
        ))}
      </div>
      <input
        style={{ ...S.input, marginBottom: 12 }}
        placeholder="Notebook title"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        maxLength={140}
        aria-label="Notebook title"
      />
      {kind === 'group' && (
        <input
          style={{ ...S.input, marginBottom: 12 }}
          placeholder="Share into Space ID (you must be a member)"
          value={spaceId}
          onChange={(e) => setSpaceId(e.target.value)}
          aria-label="Space ID to share group notebook into"
        />
      )}
      {error && <p style={{ color: '#FF3B30', fontSize: 13, marginBottom: 10 }}>{error}</p>}
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
        <button style={S.ghostBtn} onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        <button style={S.primaryBtn(busy || title.trim() === '')} onClick={submit} disabled={busy || title.trim() === ''}>
          {busy ? 'Creating…' : 'Create'}
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD SOURCE FORM
// ─────────────────────────────────────────────────────────────────────────────

const SOURCE_TYPES: Array<{ value: 'note' | 'sermon' | 'verse_range' | 'doc' | 'chat_checkpoint'; label: string }> = [
  { value: 'note', label: 'Note' },
  { value: 'sermon', label: 'Sermon' },
  { value: 'verse_range', label: 'Verse range' },
  { value: 'doc', label: 'Document' },
  { value: 'chat_checkpoint', label: 'Chat checkpoint' },
];

function AddSource({
  notebookId,
  onAdded,
}: {
  notebookId: string;
  onAdded: () => void;
}): JSX.Element {
  const [sourceType, setSourceType] = useState<typeof SOURCE_TYPES[number]['value']>('note');
  const [title, setTitle] = useState('');
  const [pointer, setPointer] = useState('');
  const [content, setContent] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  const submit = async () => {
    if (busy || content.trim() === '' || pointer.trim() === '') return;
    setBusy(true);
    setError(null);
    try {
      const res = await ingestSource({
        notebookId,
        sourceType,
        pointer: pointer.trim(),
        title: title.trim() || undefined,
        content: content.trim(),
      });
      if (!res.success) {
        setError(res.error || 'Could not index source.');
        return;
      }
      setTitle('');
      setPointer('');
      setContent('');
      setOpen(false);
      onAdded();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not add source.');
    } finally {
      setBusy(false);
    }
  };

  if (!open) {
    return (
      <button style={S.primaryBtn(false)} onClick={() => setOpen(true)}>
        + Add source
      </button>
    );
  }

  return (
    <div style={S.card}>
      <div style={S.sectionLabel}>Add a source</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginBottom: 12 }}>
        {SOURCE_TYPES.map((t) => (
          <button
            key={t.value}
            style={S.pill(sourceType === t.value)}
            onClick={() => setSourceType(t.value)}
            aria-pressed={sourceType === t.value}
          >
            {t.label}
          </button>
        ))}
      </div>
      <input
        style={{ ...S.input, marginBottom: 10 }}
        placeholder="Source title (optional)"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        aria-label="Source title"
      />
      <input
        style={{ ...S.input, marginBottom: 10 }}
        placeholder="Pointer / deep link to the source of truth"
        value={pointer}
        onChange={(e) => setPointer(e.target.value)}
        aria-label="Source pointer"
      />
      <textarea
        style={{ ...S.textarea, marginBottom: 10 }}
        placeholder="Paste the note / sermon text / passage to index…"
        value={content}
        onChange={(e) => setContent(e.target.value)}
        aria-label="Source content"
      />
      {error && <p style={{ color: '#FF3B30', fontSize: 13, marginBottom: 10 }}>{error}</p>}
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
        <button style={S.ghostBtn} onClick={() => setOpen(false)} disabled={busy}>
          Cancel
        </button>
        <button
          style={S.primaryBtn(busy || content.trim() === '' || pointer.trim() === '')}
          onClick={submit}
          disabled={busy || content.trim() === '' || pointer.trim() === ''}
        >
          {busy ? 'Indexing…' : 'Index source'}
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTEBOOK DETAIL — sources + grounded query UX (+ ANSWER / REFUSE states)
// ─────────────────────────────────────────────────────────────────────────────

function NotebookDetail({
  notebook,
  onBack,
  onChanged,
}: {
  notebook: Notebook;
  onBack: () => void;
  onChanged: () => void;
}): JSX.Element {
  const [refresh, setRefresh] = useState(0);
  const [queryText, setQueryText] = useState('');
  const [asking, setAsking] = useState(false);
  const [result, setResult] = useState<NotebookQueryResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  // notebook prop may have stale counts after an ingest; force re-read via key.
  const sourceCount = notebook.sourceRefs?.length ?? 0;

  const ask = useCallback(
    async (text: string) => {
      const q = text.trim();
      if (asking || q === '') return;
      setAsking(true);
      setError(null);
      setResult(null);
      try {
        const res = await queryNotebook({ notebookId: notebook.id, query: q });
        setResult(res);
      } catch (err) {
        // Infrastructure / network failure → ERROR state (distinct from REFUSE).
        setError(err instanceof Error ? err.message : 'The study assistant is temporarily unavailable.');
      } finally {
        setAsking(false);
      }
    },
    [asking, notebook.id],
  );

  return (
    <div>
      <button style={{ ...S.ghostBtn, paddingLeft: 0, marginBottom: 12 }} onClick={onBack}>
        ← All notebooks
      </button>

      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 6 }}>
        <span style={{ fontSize: 30 }} aria-hidden="true">
          {KIND_META[notebook.kind].icon}
        </span>
        <div>
          <h1 style={{ ...S.heading, marginBottom: 2 }}>{notebook.title}</h1>
          <div style={S.nbMeta}>
            {KIND_META[notebook.kind].label}
            {' · '}
            {sourceCount} {sourceCount === 1 ? 'source' : 'sources'}
            {notebook.kind === 'group' && notebook.sharedWithSpaceId ? ' · Shared with a Space' : ''}
          </div>
        </div>
      </div>

      <hr style={S.divider} />

      {/* Sources + add */}
      <div style={S.sectionLabel}>Sources</div>
      {sourceCount === 0 ? (
        <p style={{ fontSize: 14, color: tokens.textSub, marginBottom: 14 }}>
          No sources yet. Add a note, sermon, or passage to ground your answers.
        </p>
      ) : (
        <div style={{ ...S.cardList, marginBottom: 14 }}>
          {notebook.sourceRefs.map((s, i) => (
            <div key={i} style={S.card}>
              <div style={{ fontSize: 14, fontWeight: 600 }}>{s.type.replace('_', ' ')}</div>
              <div style={{ fontSize: 12, color: tokens.textSub, marginTop: 2, wordBreak: 'break-all' }}>
                {s.pointer}
              </div>
            </div>
          ))}
        </div>
      )}
      <div style={{ marginBottom: 22 }}>
        <AddSource
          notebookId={notebook.id}
          onAdded={() => {
            setRefresh((r) => r + 1);
            onChanged();
          }}
        />
      </div>

      <hr style={S.divider} />

      {/* Grounded query UX */}
      <div style={S.sectionLabel}>Ask this notebook</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginBottom: 12 }}>
        {SUGGESTED_PROMPTS.map((s) => (
          <button
            key={s.label}
            style={S.suggestPill}
            onClick={() => {
              setQueryText(s.prompt);
              ask(s.prompt);
            }}
            disabled={asking}
          >
            {s.label}
          </button>
        ))}
      </div>
      <textarea
        style={{ ...S.textarea, marginBottom: 10 }}
        placeholder='e.g. "Summarize my notes from this sermon" or "Compare with Romans 8"'
        value={queryText}
        onChange={(e) => setQueryText(e.target.value)}
        aria-label="Ask a grounded question"
      />
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 18 }}>
        <button
          style={S.primaryBtn(asking || queryText.trim() === '')}
          onClick={() => ask(queryText)}
          disabled={asking || queryText.trim() === ''}
        >
          {asking ? 'Thinking…' : 'Ask'}
        </button>
      </div>

      {/* ── ERROR state (infrastructure) — red, alarming, retry ────────────── */}
      {error && (
        <div style={S.errorCard} role="alert">
          <div style={{ fontWeight: 600, marginBottom: 4 }}>Something went wrong</div>
          <div style={{ fontSize: 14, color: tokens.textSub }}>{error}</div>
          <div style={{ marginTop: 10 }}>
            <button style={S.primaryBtn(false)} onClick={() => ask(queryText)}>
              Try again
            </button>
          </div>
        </div>
      )}

      {/* ── REFUSE state (ungrounded) — calm, blue, "add sources" affordance ─ */}
      {result && result.grounded === false && (
        <div style={S.refuseCard} role="status">
          <div style={{ fontWeight: 600, marginBottom: 4 }}>I can only answer from your sources</div>
          <div style={{ fontSize: 14, color: tokens.textSub }}>{result.message}</div>
          <div style={{ marginTop: 12 }}>
            <AddSource
              notebookId={notebook.id}
              onAdded={() => {
                setRefresh((r) => r + 1);
                onChanged();
                setResult(null);
              }}
            />
          </div>
        </div>
      )}

      {/* ── ANSWER state (grounded) — answer + per-chunk citations ──────────── */}
      {result && result.grounded === true && (
        <div>
          <div style={S.answerCard}>{result.answer}</div>
          <Citations answer={result} />
        </div>
      )}

      {/* hidden refresh key to keep lints happy about setRefresh usage */}
      <span style={{ display: 'none' }}>{refresh}</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN — owns LOADING / EMPTY / LIST / ERROR(list) routing
// ─────────────────────────────────────────────────────────────────────────────

export default function NotebooksScreen({ userId }: NotebooksScreenProps): JSX.Element {
  const [notebooks, setNotebooks] = useState<Notebook[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [selected, setSelected] = useState<Notebook | null>(null);

  const load = useCallback(async () => {
    setLoadError(null);
    try {
      const list = await listNotebooks(userId);
      setNotebooks(list);
      // keep selected in sync with refreshed data
      setSelected((cur) => (cur ? list.find((n) => n.id === cur.id) ?? null : null));
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Unable to load notebooks.');
      setNotebooks([]);
    }
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);

  const remove = async (id: string) => {
    try {
      await softDeleteNotebook(id);
      await load();
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Could not delete notebook.');
    }
  };

  // ── DETAIL view ────────────────────────────────────────────────────────────
  if (selected) {
    return (
      <main style={S.screen} aria-label="Notebook detail">
        <NotebookDetail
          notebook={selected}
          onBack={() => setSelected(null)}
          onChanged={load}
        />
      </main>
    );
  }

  return (
    <main style={S.screen} aria-label="Amen Notebooks">
      <h1 style={S.heading}>Notebooks</h1>
      <p style={S.subheading}>
        Grounded study from your own sources. Every answer cites what it used — never a guess.
      </p>

      {/* ── LIST-level ERROR ───────────────────────────────────────────────── */}
      {loadError && (
        <div style={{ ...S.errorCard, marginBottom: 16 }} role="alert">
          <div style={{ fontWeight: 600, marginBottom: 4 }}>Couldn’t load notebooks</div>
          <div style={{ fontSize: 14, color: tokens.textSub }}>{loadError}</div>
          <div style={{ marginTop: 10 }}>
            <button style={S.primaryBtn(false)} onClick={load}>
              Retry
            </button>
          </div>
        </div>
      )}

      {/* ── Create form ────────────────────────────────────────────────────── */}
      {creating && (
        <div style={{ marginBottom: 18 }}>
          <CreateNotebook
            onCreated={() => {
              setCreating(false);
              load();
            }}
            onCancel={() => setCreating(false)}
          />
        </div>
      )}

      {/* ── LOADING ────────────────────────────────────────────────────────── */}
      {notebooks === null && !loadError && <p style={S.spinner}>Loading your notebooks…</p>}

      {/* ── EMPTY ──────────────────────────────────────────────────────────── */}
      {notebooks !== null && notebooks.length === 0 && !creating && (
        <div style={{ ...S.card, textAlign: 'center', padding: '40px 20px' }}>
          <div style={{ fontSize: 40, marginBottom: 10 }} aria-hidden="true">
            📓
          </div>
          <div style={{ fontSize: 17, fontWeight: 600, marginBottom: 6 }}>No notebooks yet</div>
          <p style={{ fontSize: 14, color: tokens.textSub, marginBottom: 16 }}>
            Create one for a sermon, study, prayer journal, project, group, or event — then add the
            sources you want grounded answers from.
          </p>
          <button style={S.primaryBtn(false)} onClick={() => setCreating(true)}>
            Create your first notebook
          </button>
        </div>
      )}

      {/* ── LIST ───────────────────────────────────────────────────────────── */}
      {notebooks !== null && notebooks.length > 0 && (
        <>
          {!creating && (
            <div style={{ marginBottom: 16 }}>
              <button style={S.primaryBtn(false)} onClick={() => setCreating(true)}>
                + New notebook
              </button>
            </div>
          )}
          <div style={S.cardList}>
            {notebooks.map((nb) => (
              <div key={nb.id} style={S.card}>
                <button style={S.nbRow} onClick={() => setSelected(nb)} aria-label={`Open ${nb.title}`}>
                  <span style={S.nbIcon} aria-hidden="true">
                    {KIND_META[nb.kind].icon}
                  </span>
                  <span style={{ flex: 1 }}>
                    <span style={S.nbTitle}>{nb.title}</span>
                    <span style={S.nbMeta}>
                      {KIND_META[nb.kind].label}
                      {' · '}
                      {(nb.sourceRefs?.length ?? 0)}{' '}
                      {(nb.sourceRefs?.length ?? 0) === 1 ? 'source' : 'sources'}
                      {nb.kind === 'group' && nb.sharedWithSpaceId ? ' · Shared' : ''}
                    </span>
                  </span>
                </button>
                <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 6 }}>
                  <button
                    style={S.destructiveBtn}
                    onClick={() => remove(nb.id)}
                    aria-label={`Delete ${nb.title}`}
                  >
                    Delete
                  </button>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </main>
  );
}
