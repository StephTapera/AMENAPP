/**
 * SelahReaderSurface.jsx
 *
 * Main full-screen Bible reader surface for Selah.
 *
 * Architecture:
 *   - Full-screen layout on #F2F2F3 page background (§1)
 *   - Frosted glass navbar (§4): back button (circular glass), title, more menu
 *   - SelahReaderControls sub-bar: translation + navigation controls
 *   - Reader body: chapter text with verse numbers; verse tap → context menu
 *   - Liquid Glass context menu (§6): Highlight / Add Note / Cross References /
 *     Original Language / Check against Scripture
 *   - SelahAnnotationPanel bottom sheet: shown for highlight/note modes
 *   - Bottom floating nav: prev/next chapter glass pills
 *
 * Context menu is HIDDEN by default; appears ONLY on deliberate verse tap.
 * NO vanity counters (no likes, shares, view counts) anywhere.
 *
 * @prop {string}   book          — current book name, e.g. "James"
 * @prop {number}   chapter       — current chapter number
 * @prop {Array<{number: number, text: string}>} verses — current chapter verses
 * @prop {import('../selah.contracts').SelahNote[]} notes — user notes for this chapter
 * @prop {(noteData: Partial<import('../selah.contracts').SelahNote>) => void} onCreateNote
 * @prop {(noteId: string) => void} onDeleteNote — soft-delete only; sets deletedAt
 * @prop {(verse: {number: number, text: string}) => void} onCheckAgainstScripture
 *   Entry point for Agent D's Berean discernment component.
 * @prop {(verseRef: string) => void} onFetchCrossReferences
 * @prop {(verseRef: string) => void} onOriginalLanguage
 *
 * Design tokens used (all from GLASS_TOKENS in selah.contracts.ts):
 *   §1 pageBackground, textPrimary, textSecondary
 *   §4 lightGlassFill, lightGlassBlur, lightGlassSaturate, lightGlassHairlineTop
 *   §6 contextMenuFill, contextMenuBlur, contextMenuRadius
 *   §8 highlightColors (applied as verse background)
 *
 * FORBIDDEN: vanity counters, hard delete, gold (#C9A84C / #FFD97D),
 *   purple (#7B68EE), cosmic gradients, Cormorant Garamond.
 */

import React, {
  useState,
  useCallback,
  useRef,
  useEffect,
  useMemo,
} from 'react';
import './selahGlass.css';
import SelahAnnotationPanel from './SelahAnnotationPanel.jsx';
import SelahReaderControls from './SelahReaderControls.jsx';

// §8 Highlight palette — solid background colors for highlighted verses
const HIGHLIGHT_BG = {
  cyan:     'rgba(100,200,220,0.25)',
  amber:    'rgba(255,180,50,0.25)',
  pink:     'rgba(255,100,150,0.20)',
  lavender: 'rgba(160,130,255,0.22)',
};

// Default available translations (reader path — may include licensed versions for display).
// LEGAL NOTE: These ids are passed to onTranslationChange only; they must NEVER be
// forwarded to the AI citation engine by the caller. Only BSB/WEB/KJV may enter the AI path.
const DEFAULT_TRANSLATIONS = ['NIV', 'ESV', 'KJV', 'NLT', 'BSB'];

// ─── Context Menu ──────────────────────────────────────────────────────────────

/**
 * VerseContextMenu — Liquid Glass popup that appears on verse tap (§6).
 * Hidden by default. Positioned adjacent to the tapped verse.
 *
 * Actions:
 *   Highlight → opens annotation panel in 'highlight' mode
 *   Add Note  → opens annotation panel in 'note' mode
 *   Cross References → calls onFetchCrossReferences(verseRef)
 *   Original Language → calls onOriginalLanguage(verseRef)
 *   Check against Scripture → calls onCheckAgainstScripture(verse) [Agent D entry point]
 */
function VerseContextMenu({ verseRef, verse, position, onHighlight, onAddNote, onCrossReferences, onOriginalLanguage, onCheckAgainstScripture, onDismiss }) {
  const menuRef = useRef(null);

  // Close on outside click or Escape
  useEffect(() => {
    const handleKey = (e) => {
      if (e.key === 'Escape') onDismiss();
    };
    const handleClick = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) onDismiss();
    };
    document.addEventListener('keydown', handleKey);
    document.addEventListener('mousedown', handleClick);
    return () => {
      document.removeEventListener('keydown', handleKey);
      document.removeEventListener('mousedown', handleClick);
    };
  }, [onDismiss]);

  const menuItems = [
    {
      icon: '✦',
      label: 'Highlight',
      action: onHighlight,
      ariaLabel: `Highlight ${verseRef}`,
    },
    {
      icon: '✎',
      label: 'Add Note',
      action: onAddNote,
      ariaLabel: `Add note to ${verseRef}`,
    },
    {
      icon: '⇌',
      label: 'Cross References',
      action: () => {
        onCrossReferences(verseRef);
        onDismiss();
      },
      ariaLabel: `View cross references for ${verseRef}`,
    },
    {
      icon: 'α',
      label: 'Original Language',
      action: () => {
        onOriginalLanguage(verseRef);
        onDismiss();
      },
      ariaLabel: `View original language for ${verseRef}`,
    },
    {
      icon: '⊕',
      label: 'Check against Scripture',
      action: () => {
        // Entry point for Agent D's Berean discernment component.
        // Passes the full verse object (number + text); Agent D receives it
        // and triggers the discernment pipeline against open-licensed text only.
        onCheckAgainstScripture(verse);
        onDismiss();
      },
      ariaLabel: `Check ${verseRef} against Scripture`,
      separator: true, // visual separator before this item
    },
  ];

  // Compute menu position, keeping it within viewport bounds
  const style = {
    position: 'fixed',
    zIndex: 300,
    top: position.y,
    left: Math.min(position.x, window.innerWidth - 220),
    width: 210,
  };

  return (
    <div
      ref={menuRef}
      className="selah-context-menu"
      style={style}
      role="menu"
      aria-label={`Actions for ${verseRef}`}
    >
      {menuItems.map((item, idx) => (
        <React.Fragment key={item.label}>
          {item.separator && <div className="selah-context-menu-divider" aria-hidden="true" />}
          <button
            type="button"
            role="menuitem"
            className="selah-context-menu-item"
            aria-label={item.ariaLabel}
            onClick={item.action}
          >
            <span
              aria-hidden="true"
              style={{ width: 22, textAlign: 'center', color: '#8A8A8E', fontSize: 16 }}
            >
              {item.icon}
            </span>
            <span style={{ fontSize: 15, color: '#0A0A0A' }}>{item.label}</span>
          </button>
        </React.Fragment>
      ))}
    </div>
  );
}

// ─── Verse Row ─────────────────────────────────────────────────────────────────

/**
 * VerseRow — a single rendered verse with its number.
 * Applies highlight background when a matching note exists.
 * Tap handler exposes the context menu.
 */
function VerseRow({ verse, verseRef, noteForVerse, onVersePress }) {
  const highlightColor = noteForVerse?.kind === 'highlight' && noteForVerse.color
    ? noteForVerse.color
    : null;

  return (
    <button
      type="button"
      aria-label={`${verseRef}: ${verse.text}. Tap for verse actions.`}
      onClick={(e) => {
        const rect = e.currentTarget.getBoundingClientRect();
        onVersePress(verse, verseRef, {
          x: rect.left,
          y: rect.bottom + 6,
        });
      }}
      style={{
        display: 'block',
        width: '100%',
        textAlign: 'left',
        background: highlightColor ?? 'transparent',
        border: 'none',
        borderRadius: 8,
        padding: '6px 8px',
        cursor: 'pointer',
        marginBottom: 2,
        transition: 'background-color 0.15s ease',
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
      }}
    >
      {/* Verse number */}
      <sup
        aria-hidden="true"
        style={{
          fontSize: 11,
          fontWeight: 600,
          color: '#8A8A8E',
          marginRight: 6,
          verticalAlign: 'super',
          lineHeight: 0,
          userSelect: 'none',
        }}
      >
        {verse.number}
      </sup>
      {/* Verse text */}
      <span
        style={{
          fontSize: 17,
          lineHeight: 1.65,
          color: '#0A0A0A',
          fontWeight: 400,
          letterSpacing: 0.1,
        }}
      >
        {verse.text}
      </span>
    </button>
  );
}

// ─── Main Component ────────────────────────────────────────────────────────────

export default function SelahReaderSurface({
  book,
  chapter,
  verses,
  notes,
  onCreateNote,
  onDeleteNote,
  onCheckAgainstScripture,
  onFetchCrossReferences,
  onOriginalLanguage,
}) {
  // ── Local state ──────────────────────────────────────────────────────────────
  const [activeVerse, setActiveVerse] = useState(null);       // { verse, verseRef, position }
  const [contextMenuOpen, setContextMenuOpen] = useState(false); // hidden by default
  const [annotationMode, setAnnotationMode] = useState(null); // 'highlight'|'note'|null
  const [currentTranslation, setCurrentTranslation] = useState('ESV');
  const [currentBook, setCurrentBook] = useState(book);
  const [currentChapter, setCurrentChapter] = useState(chapter);
  const [moreMenuOpen, setMoreMenuOpen] = useState(false);
  const moreMenuRef = useRef(null);

  // Sync props → state when navigation happens externally
  useEffect(() => {
    setCurrentBook(book);
    setCurrentChapter(chapter);
  }, [book, chapter]);

  // Close the more-menu on outside click
  useEffect(() => {
    if (!moreMenuOpen) return;
    const handler = (e) => {
      if (moreMenuRef.current && !moreMenuRef.current.contains(e.target)) {
        setMoreMenuOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [moreMenuOpen]);

  // ── Build a map: verseRef → note (for highlight rendering) ─────────────────
  const notesByRef = useMemo(() => {
    const map = {};
    if (!notes) return map;
    notes.forEach((n) => {
      if (!n.deletedAt) {
        map[n.verseRef] = n;
      }
    });
    return map;
  }, [notes]);

  // ── Verse tap handler ──────────────────────────────────────────────────────
  const handleVersePress = useCallback((verse, verseRef, position) => {
    setActiveVerse({ verse, verseRef, position });
    setContextMenuOpen(true); // context menu appears ONLY on explicit tap
    setAnnotationMode(null);
  }, []);

  const handleDismissContextMenu = useCallback(() => {
    setContextMenuOpen(false);
    setActiveVerse(null);
  }, []);

  // ── Context menu action handlers ───────────────────────────────────────────
  const handleHighlight = useCallback(() => {
    setContextMenuOpen(false);
    setAnnotationMode('highlight');
  }, []);

  const handleAddNote = useCallback(() => {
    setContextMenuOpen(false);
    setAnnotationMode('note');
  }, []);

  // ── Annotation panel handlers ──────────────────────────────────────────────
  const handleCreateNote = useCallback(
    (noteData) => {
      // Delegate to parent; parent writes to Firestore users/{uid}/selahNotes/{noteId}
      // LEGAL: translationRead is set by the parent from currentTranslation (display path only;
      //        the parent must never forward this to the AI citation engine).
      onCreateNote({
        ...noteData,
        verseRef: activeVerse?.verseRef ?? noteData.verseRef,
      });
    },
    [activeVerse, onCreateNote]
  );

  const handleDeleteNote = useCallback(
    (noteId) => {
      // Soft-delete only: parent sets deletedAt timestamp — no hard-delete path.
      onDeleteNote(noteId);
    },
    [onDeleteNote]
  );

  const handleDismissAnnotation = useCallback(() => {
    setAnnotationMode(null);
    setActiveVerse(null);
  }, []);

  // ── Navigation handlers ────────────────────────────────────────────────────
  const handlePrevChapter = useCallback(() => {
    if (currentChapter > 1) {
      setCurrentChapter((c) => c - 1);
    }
  }, [currentChapter]);

  const handleNextChapter = useCallback(() => {
    setCurrentChapter((c) => c + 1);
  }, []);

  const handleNavigate = useCallback((newBook, newChapter) => {
    setCurrentBook(newBook);
    setCurrentChapter(newChapter);
  }, []);

  // Stub handlers for controls that delegate to parent
  const handleAudioToggle = useCallback(() => {
    // Audio playback toggled — parent wires to AVPlayer / playback service
  }, []);

  const handleSearchOpen = useCallback(() => {
    // Search opened — parent wires to in-reader search overlay
  }, []);

  // ── Existing note for active verse (for edit flow) ─────────────────────────
  const existingNoteForActiveVerse = activeVerse
    ? notesByRef[activeVerse.verseRef]
    : undefined;

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <div
      className="selah-page-bg"
      style={{
        display: 'flex',
        flexDirection: 'column',
        minHeight: '100vh',
        position: 'relative',
      }}
    >
      {/* ── Frosted glass navbar (§4) ──────────────────────────────────────── */}
      <header
        style={{
          position: 'sticky',
          top: 0,
          zIndex: 50,
          backgroundColor: 'rgba(255,255,255,0.72)',
          backdropFilter: 'blur(24px) saturate(1.2)',
          WebkitBackdropFilter: 'blur(24px) saturate(1.2)',
          borderBottom: '1px solid rgba(255,255,255,0.6)',
          boxShadow: '0 1px 4px rgba(0,0,0,0.06)',
          padding: '12px 16px',
        }}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            maxWidth: 680,
            margin: '0 auto',
          }}
        >
          {/* Back button — circular glass §4 */}
          <button
            type="button"
            className="selah-glass-circle"
            aria-label="Go back"
            onClick={() => {/* caller handles navigation */}}
          >
            {/* SF-style chevron left */}
            <svg
              aria-hidden="true"
              width="10"
              height="16"
              viewBox="0 0 10 16"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M8.5 1.5L2 8L8.5 14.5"
                stroke="#0A0A0A"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </button>

          {/* Chapter title — centered */}
          <h1
            style={{
              flex: 1,
              textAlign: 'center',
              fontSize: 17,
              fontWeight: 600,
              color: '#0A0A0A',
              margin: 0,
              letterSpacing: -0.2,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {currentBook} {currentChapter}
          </h1>

          {/* More menu — circular glass §4 */}
          <div ref={moreMenuRef} style={{ position: 'relative' }}>
            <button
              type="button"
              className="selah-glass-circle"
              aria-label="More options"
              aria-haspopup="menu"
              aria-expanded={moreMenuOpen}
              onClick={() => setMoreMenuOpen((v) => !v)}
            >
              {/* Ellipsis */}
              <svg
                aria-hidden="true"
                width="18"
                height="4"
                viewBox="0 0 18 4"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <circle cx="2" cy="2" r="1.5" fill="#0A0A0A" />
                <circle cx="9" cy="2" r="1.5" fill="#0A0A0A" />
                <circle cx="16" cy="2" r="1.5" fill="#0A0A0A" />
              </svg>
            </button>

            {moreMenuOpen && (
              <div
                className="selah-context-menu"
                style={{
                  position: 'absolute',
                  top: 'calc(100% + 8px)',
                  right: 0,
                  width: 200,
                  zIndex: 100,
                }}
                role="menu"
                aria-label="Reader options"
              >
                {[
                  { label: 'Font Size', icon: 'A', action: () => setMoreMenuOpen(false) },
                  { label: 'Reading Plan', icon: '≡', action: () => setMoreMenuOpen(false) },
                  { label: 'Share Passage', icon: '↗', action: () => setMoreMenuOpen(false) },
                ].map((item) => (
                  <button
                    key={item.label}
                    type="button"
                    role="menuitem"
                    className="selah-context-menu-item"
                    onClick={item.action}
                  >
                    <span
                      aria-hidden="true"
                      style={{ width: 22, textAlign: 'center', color: '#8A8A8E', fontSize: 14 }}
                    >
                      {item.icon}
                    </span>
                    <span style={{ fontSize: 15 }}>{item.label}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Reader controls sub-bar */}
        <div
          style={{
            maxWidth: 680,
            margin: '10px auto 0',
          }}
        >
          <SelahReaderControls
            currentTranslation={currentTranslation}
            availableTranslations={DEFAULT_TRANSLATIONS}
            currentBook={currentBook}
            currentChapter={currentChapter}
            onTranslationChange={setCurrentTranslation}
            onNavigate={handleNavigate}
            onAudioToggle={handleAudioToggle}
            onSearchOpen={handleSearchOpen}
          />
        </div>
      </header>

      {/* ── Reader body ────────────────────────────────────────────────────── */}
      <main
        role="main"
        aria-label={`${currentBook} chapter ${currentChapter}`}
        style={{
          flex: 1,
          padding: '24px 20px 120px', // bottom padding clears floating nav
          maxWidth: 680,
          margin: '0 auto',
          width: '100%',
          boxSizing: 'border-box',
        }}
      >
        {/* Chapter heading */}
        <h2
          aria-label={`Chapter ${currentChapter}`}
          style={{
            fontSize: 13,
            fontWeight: 700,
            color: '#8A8A8E',
            textTransform: 'uppercase',
            letterSpacing: 1,
            marginBottom: 20,
            marginTop: 0,
          }}
        >
          Chapter {currentChapter}
        </h2>

        {/* Verse list */}
        {verses && verses.length > 0 ? (
          <div role="list" aria-label={`Verses of ${currentBook} ${currentChapter}`}>
            {verses.map((verse) => {
              const verseRef = `${currentBook} ${currentChapter}:${verse.number}`;
              return (
                <div key={verse.number} role="listitem">
                  <VerseRow
                    verse={verse}
                    verseRef={verseRef}
                    noteForVerse={notesByRef[verseRef] ?? null}
                    onVersePress={handleVersePress}
                  />
                </div>
              );
            })}
          </div>
        ) : (
          /* Empty state — never shows a loading spinner to avoid flash */
          <p
            style={{
              color: '#8A8A8E',
              fontSize: 15,
              textAlign: 'center',
              marginTop: 60,
            }}
          >
            Loading passage…
          </p>
        )}
      </main>

      {/* ── Bottom floating chapter navigation ────────────────────────────── */}
      <nav
        aria-label="Chapter navigation"
        style={{
          position: 'fixed',
          bottom: 28,
          left: 0,
          right: 0,
          display: 'flex',
          justifyContent: 'center',
          gap: 16,
          zIndex: 40,
          pointerEvents: 'none', // let taps pass through except on buttons
        }}
      >
        {/* Previous chapter */}
        <button
          type="button"
          className="selah-glass-pill"
          aria-label={`Previous chapter: ${currentBook} ${currentChapter - 1}`}
          disabled={currentChapter <= 1}
          onClick={handlePrevChapter}
          style={{
            pointerEvents: 'auto',
            opacity: currentChapter <= 1 ? 0.35 : 1,
            gap: 8,
          }}
        >
          <svg
            aria-hidden="true"
            width="8"
            height="14"
            viewBox="0 0 8 14"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M7 1L1.5 7L7 13"
              stroke="#0A0A0A"
              strokeWidth="1.6"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
          <span>Previous</span>
        </button>

        {/* Next chapter */}
        <button
          type="button"
          className="selah-glass-pill"
          aria-label={`Next chapter: ${currentBook} ${currentChapter + 1}`}
          onClick={handleNextChapter}
          style={{ pointerEvents: 'auto', gap: 8 }}
        >
          <span>Next</span>
          <svg
            aria-hidden="true"
            width="8"
            height="14"
            viewBox="0 0 8 14"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M1 1L6.5 7L1 13"
              stroke="#0A0A0A"
              strokeWidth="1.6"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>
      </nav>

      {/* ── Verse context menu (§6) — HIDDEN until verse tap ──────────────── */}
      {contextMenuOpen && activeVerse && (
        <VerseContextMenu
          verseRef={activeVerse.verseRef}
          verse={activeVerse.verse}
          position={activeVerse.position}
          onHighlight={handleHighlight}
          onAddNote={handleAddNote}
          onCrossReferences={onFetchCrossReferences}
          onOriginalLanguage={onOriginalLanguage}
          onCheckAgainstScripture={onCheckAgainstScripture}
          onDismiss={handleDismissContextMenu}
        />
      )}

      {/* ── Annotation panel bottom sheet ────────────────────────────────── */}
      {annotationMode && activeVerse && (
        <SelahAnnotationPanel
          verseRef={activeVerse.verseRef}
          mode={annotationMode}
          existingNote={existingNoteForActiveVerse}
          onCreateNote={handleCreateNote}
          onDeleteNote={handleDeleteNote}
          onDismiss={handleDismissAnnotation}
        />
      )}
    </div>
  );
}
