/**
 * SelahReaderControls.jsx
 *
 * Horizontal glass pill toolbar placed at the top of the Selah reader.
 * Contains: translation version picker, book/chapter picker, audio toggle,
 * and search opener — all in frosted glass §4 containers.
 *
 * @prop {string}   currentTranslation      — abbreviation of active translation, e.g. "ESV"
 * @prop {string[]} availableTranslations   — list of available translation IDs
 * @prop {string}   currentBook             — current book name, e.g. "James"
 * @prop {number}   currentChapter          — current chapter number
 * @prop {(id: string) => void}             onTranslationChange — called when user picks a new version
 * @prop {(book: string, chapter: number) => void} onNavigate — called when user selects book+chapter
 * @prop {() => void} onAudioToggle         — toggle audio playback
 * @prop {() => void} onSearchOpen          — open in-reader search
 *
 * Design tokens used (all from GLASS_TOKENS in selah.contracts.ts):
 *   §4  Light frosted glass for all pill / circle controls
 *   §5  Segmented control for book/chapter picker (when open)
 *
 * FORBIDDEN: vanity counters, gold (#C9A84C / #FFD97D), purple (#7B68EE),
 *   cosmic gradients, Cormorant Garamond.
 */

import React, { useState, useRef, useEffect, useCallback } from 'react';
import './selahGlass.css';

// Books of the Bible — used by the book/chapter picker
const BIBLE_BOOKS = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
  'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
  '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra',
  'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs',
  'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah', 'Lamentations',
  'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
  'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk',
  'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
  'Matthew', 'Mark', 'Luke', 'John', 'Acts',
  'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
  'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
  '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews',
  'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
  'Jude', 'Revelation',
];

// Chapter counts per book (index aligned to BIBLE_BOOKS)
const CHAPTER_COUNTS = [
  50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10,
  13, 10, 42, 150, 31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9,
  1, 4, 7, 3, 3, 3, 2, 14, 4,
  28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4,
  3, 1, 13, 5, 1, 1, 1, 1, 22,
];

/**
 * DropdownList — light glass floating dropdown panel.
 */
function DropdownList({ items, selectedId, onSelect, ariaLabel, id }) {
  return (
    <div
      id={id}
      role="listbox"
      aria-label={ariaLabel}
      style={{
        position: 'absolute',
        top: 'calc(100% + 8px)',
        left: 0,
        minWidth: 160,
        backgroundColor: 'rgba(250,250,250,0.92)',
        backdropFilter: 'blur(30px) saturate(1.2)',
        WebkitBackdropFilter: 'blur(30px) saturate(1.2)',
        borderRadius: 16,
        boxShadow: '0 8px 32px rgba(0,0,0,0.12), 0 2px 8px rgba(0,0,0,0.06)',
        zIndex: 100,
        overflow: 'hidden',
        maxHeight: 280,
        overflowY: 'auto',
      }}
    >
      {items.map((item, idx) => (
        <button
          key={item}
          role="option"
          aria-selected={item === selectedId}
          onClick={() => onSelect(item)}
          type="button"
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            width: '100%',
            padding: '11px 16px',
            border: 'none',
            background: item === selectedId ? 'rgba(0,0,0,0.05)' : 'transparent',
            cursor: 'pointer',
            fontSize: 15,
            color: '#0A0A0A',
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
            fontWeight: item === selectedId ? 600 : 400,
            borderTop: idx > 0 ? '1px solid rgba(0,0,0,0.05)' : 'none',
            minHeight: 44,
            textAlign: 'left',
          }}
        >
          <span>{item}</span>
          {item === selectedId && (
            <span aria-hidden="true" style={{ fontSize: 14, color: '#0A0A0A' }}>✓</span>
          )}
        </button>
      ))}
    </div>
  );
}

/**
 * TranslationPicker — glass capsule with dropdown for version selection.
 * NOTE: The displayed list (NIV, ESV, KJV, NLT, BSB) is the HUMAN READER path.
 * onTranslationChange passes only the id string to the caller, never verse text.
 * The caller is responsible for ensuring licensed translations (ESV/NIV/NLT)
 * are never passed to the AI citation engine.
 */
function TranslationPicker({ currentTranslation, availableTranslations, onTranslationChange }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const handleSelect = useCallback(
    (id) => {
      onTranslationChange(id);
      setOpen(false);
    },
    [onTranslationChange]
  );

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button
        type="button"
        className="selah-glass-pill"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls="translation-listbox"
        aria-label={`Translation: ${currentTranslation}. Tap to change.`}
        onClick={() => setOpen((v) => !v)}
      >
        <span style={{ fontWeight: 600 }}>{currentTranslation}</span>
        <span aria-hidden="true" style={{ fontSize: 11, color: '#8A8A8E' }}>
          {open ? '▲' : '▼'}
        </span>
      </button>

      {open && (
        <DropdownList
          id="translation-listbox"
          items={availableTranslations}
          selectedId={currentTranslation}
          onSelect={handleSelect}
          ariaLabel="Select Bible translation"
        />
      )}
    </div>
  );
}

/**
 * BookChapterPicker — glass capsule with two-stage book→chapter selection.
 * Stage 1: choose a book. Stage 2: choose a chapter number.
 * Calls onNavigate(book, chapter) on final selection.
 */
function BookChapterPicker({ currentBook, currentChapter, onNavigate }) {
  const [open, setOpen] = useState(false);
  const [stage, setStage] = useState('book'); // 'book' | 'chapter'
  const [pendingBook, setPendingBook] = useState(currentBook);
  const ref = useRef(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) {
        setOpen(false);
        setStage('book');
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const handleBookSelect = useCallback((book) => {
    setPendingBook(book);
    setStage('chapter');
  }, []);

  const handleChapterSelect = useCallback(
    (chapterNum) => {
      onNavigate(pendingBook, chapterNum);
      setOpen(false);
      setStage('book');
    },
    [pendingBook, onNavigate]
  );

  const bookIndex = BIBLE_BOOKS.indexOf(pendingBook);
  const chapterCount = bookIndex >= 0 ? CHAPTER_COUNTS[bookIndex] : 50;
  const chapters = Array.from({ length: chapterCount }, (_, i) => i + 1);

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button
        type="button"
        className="selah-glass-pill"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`Location: ${currentBook} chapter ${currentChapter}. Tap to navigate.`}
        onClick={() => {
          setOpen((v) => !v);
          setStage('book');
        }}
      >
        <span style={{ fontWeight: 600 }}>{currentBook} {currentChapter}</span>
        <span aria-hidden="true" style={{ fontSize: 11, color: '#8A8A8E' }}>
          {open ? '▲' : '▼'}
        </span>
      </button>

      {open && (
        <div
          style={{
            position: 'absolute',
            top: 'calc(100% + 8px)',
            left: 0,
            width: 220,
            backgroundColor: 'rgba(250,250,250,0.92)',
            backdropFilter: 'blur(30px) saturate(1.2)',
            WebkitBackdropFilter: 'blur(30px) saturate(1.2)',
            borderRadius: 16,
            boxShadow: '0 8px 32px rgba(0,0,0,0.12), 0 2px 8px rgba(0,0,0,0.06)',
            zIndex: 100,
            overflow: 'hidden',
          }}
        >
          {/* Stage header */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              padding: '10px 16px 8px',
              borderBottom: '1px solid rgba(0,0,0,0.07)',
            }}
          >
            {stage === 'chapter' && (
              <button
                type="button"
                onClick={() => setStage('book')}
                aria-label="Back to book selection"
                style={{
                  border: 'none',
                  background: 'none',
                  cursor: 'pointer',
                  fontSize: 16,
                  color: '#8A8A8E',
                  marginRight: 8,
                  padding: 0,
                  lineHeight: 1,
                }}
              >
                ‹
              </button>
            )}
            <span
              style={{
                fontSize: 12,
                fontWeight: 600,
                color: '#8A8A8E',
                textTransform: 'uppercase',
                letterSpacing: 0.5,
              }}
            >
              {stage === 'book' ? 'Select Book' : pendingBook}
            </span>
          </div>

          {/* Scrollable list */}
          <div
            role="listbox"
            aria-label={stage === 'book' ? 'Select book' : 'Select chapter'}
            style={{ maxHeight: 260, overflowY: 'auto' }}
          >
            {stage === 'book' &&
              BIBLE_BOOKS.map((book, idx) => (
                <button
                  key={book}
                  role="option"
                  aria-selected={book === currentBook}
                  type="button"
                  onClick={() => handleBookSelect(book)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    width: '100%',
                    padding: '10px 16px',
                    border: 'none',
                    background: book === currentBook ? 'rgba(0,0,0,0.05)' : 'transparent',
                    cursor: 'pointer',
                    fontSize: 14,
                    color: '#0A0A0A',
                    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                    fontWeight: book === currentBook ? 600 : 400,
                    borderTop: idx > 0 ? '1px solid rgba(0,0,0,0.04)' : 'none',
                    minHeight: 40,
                    textAlign: 'left',
                  }}
                >
                  <span>{book}</span>
                  <span aria-hidden="true" style={{ fontSize: 11, color: '#8A8A8E' }}>›</span>
                </button>
              ))}

            {stage === 'chapter' && (
              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(5, 1fr)',
                  gap: 4,
                  padding: 12,
                }}
              >
                {chapters.map((ch) => (
                  <button
                    key={ch}
                    role="option"
                    aria-selected={pendingBook === currentBook && ch === currentChapter}
                    type="button"
                    onClick={() => handleChapterSelect(ch)}
                    style={{
                      height: 40,
                      border: 'none',
                      borderRadius: 10,
                      background:
                        pendingBook === currentBook && ch === currentChapter
                          ? '#0A0A0A'
                          : 'rgba(0,0,0,0.05)',
                      color:
                        pendingBook === currentBook && ch === currentChapter
                          ? '#FFFFFF'
                          : '#0A0A0A',
                      fontWeight: 500,
                      fontSize: 14,
                      cursor: 'pointer',
                      fontFamily:
                        '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
                    }}
                    aria-label={`Chapter ${ch}`}
                  >
                    {ch}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Main Component ────────────────────────────────────────────────────────────

export default function SelahReaderControls({
  currentTranslation,
  availableTranslations,
  currentBook,
  currentChapter,
  onTranslationChange,
  onNavigate,
  onAudioToggle,
  onSearchOpen,
}) {
  return (
    <div
      role="toolbar"
      aria-label="Reader controls"
      style={{
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        flexWrap: 'wrap',
      }}
    >
      {/* Translation version picker */}
      <TranslationPicker
        currentTranslation={currentTranslation}
        availableTranslations={availableTranslations}
        onTranslationChange={onTranslationChange}
      />

      {/* Book / chapter picker */}
      <BookChapterPicker
        currentBook={currentBook}
        currentChapter={currentChapter}
        onNavigate={onNavigate}
      />

      {/* Spacer pushes icon buttons to the right */}
      <div style={{ flex: 1 }} />

      {/* Audio toggle — circular glass §4 */}
      <button
        type="button"
        className="selah-glass-circle"
        aria-label="Toggle audio playback"
        onClick={onAudioToggle}
      >
        {/* SF Symbol equivalent: play.circle */}
        <svg
          aria-hidden="true"
          width="20"
          height="20"
          viewBox="0 0 20 20"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <circle cx="10" cy="10" r="8.5" stroke="#0A0A0A" strokeWidth="1.5" />
          <path
            d="M8 7.268C8 6.772 8.537 6.466 8.96 6.728l5.04 2.732a.8.8 0 010 1.08L8.96 13.272C8.537 13.534 8 13.228 8 12.732V7.268z"
            fill="#0A0A0A"
          />
        </svg>
      </button>

      {/* Search opener — circular glass §4 */}
      <button
        type="button"
        className="selah-glass-circle"
        aria-label="Open search"
        onClick={onSearchOpen}
      >
        {/* SF Symbol equivalent: magnifyingglass */}
        <svg
          aria-hidden="true"
          width="18"
          height="18"
          viewBox="0 0 18 18"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <circle cx="7.5" cy="7.5" r="5.5" stroke="#0A0A0A" strokeWidth="1.5" />
          <path
            d="M11.5 11.5L15.5 15.5"
            stroke="#0A0A0A"
            strokeWidth="1.5"
            strokeLinecap="round"
          />
        </svg>
      </button>
    </div>
  );
}
