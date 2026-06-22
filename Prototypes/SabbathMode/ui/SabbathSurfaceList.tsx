/**
 * SabbathSurfaceList.tsx
 * Phase 2B — Sabbath Surface UI
 * Date: 2026-06-07
 *
 * Renders the 8 allowed surfaces as a tappable list inside the SabbathWindowView card.
 * Each surface is a full-width row with a monochrome icon, label, and description.
 *
 * DESIGN RULES: No borders between items, transparent background per row,
 * hover: rgba(0,0,0,0.03) with border-radius 12px.
 */

import React, { useState } from 'react';
import type { SabbathSurface } from '../contracts/SabbathTypes';
import { SabbathTokens } from './SabbathTokens';

interface SurfaceEntry {
  surface: SabbathSurface;
  icon: React.ReactNode;
  label: string;
  description: string;
}

interface SabbathSurfaceListProps {
  onSurfaceSelect: (surface: SabbathSurface) => void;
}

// Monochrome SVG icons — SF Symbols-style line icons
const ScriptureIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <rect x="3" y="2" width="11" height="16" rx="1.5" stroke="#3C3C3C" strokeWidth="1.4" />
    <line x1="6" y1="6" x2="11" y2="6" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <line x1="6" y1="9" x2="11" y2="9" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <line x1="6" y1="12" x2="9" y2="12" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <path d="M14 5v11l2-1.5L18 16V5a1 1 0 0 0-1-1h-2a1 1 0 0 0-1 1z" stroke="#3C3C3C" strokeWidth="1.4" strokeLinejoin="round" />
  </svg>
);

const PrayerIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <path d="M10 3C10 3 6 6.5 6 10.5C6 12.985 7.791 15 10 15C12.209 15 14 12.985 14 10.5C14 6.5 10 3 10 3Z" stroke="#3C3C3C" strokeWidth="1.4" strokeLinejoin="round" />
    <line x1="10" y1="15" x2="10" y2="18" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <line x1="8" y1="18" x2="12" y2="18" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
  </svg>
);

const BereanGuideIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <circle cx="10" cy="10" r="7" stroke="#3C3C3C" strokeWidth="1.4" />
    <path d="M10 7v4" stroke="#3C3C3C" strokeWidth="1.5" strokeLinecap="round" />
    <circle cx="10" cy="13.5" r="0.7" fill="#3C3C3C" />
  </svg>
);

const ChurchNotesIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <rect x="4" y="3" width="12" height="14" rx="1.5" stroke="#3C3C3C" strokeWidth="1.4" />
    <line x1="7" y1="7" x2="13" y2="7" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <line x1="7" y1="10" x2="13" y2="10" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <line x1="7" y1="13" x2="10" y2="13" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <path d="M15 2l1 1-1 1" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
  </svg>
);

const FindChurchIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <path d="M10 2L10 5" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
    <path d="M6 5h8v2L10 9 6 7V5z" stroke="#3C3C3C" strokeWidth="1.4" strokeLinejoin="round" />
    <rect x="5" y="9" width="10" height="9" rx="1" stroke="#3C3C3C" strokeWidth="1.4" />
    <rect x="8.5" y="13" width="3" height="5" rx="0.5" stroke="#3C3C3C" strokeWidth="1.2" />
  </svg>
);

const SpacesIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <circle cx="10" cy="7" r="3" stroke="#3C3C3C" strokeWidth="1.4" />
    <circle cx="4.5" cy="13.5" r="2" stroke="#3C3C3C" strokeWidth="1.2" />
    <circle cx="15.5" cy="13.5" r="2" stroke="#3C3C3C" strokeWidth="1.2" />
    <path d="M7 10.5C7 10.5 5.5 11 4.5 11.5M13 10.5C13 10.5 14.5 11 15.5 11.5" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
    <path d="M7 16C7 14.343 8.343 13 10 13C11.657 13 13 14.343 13 16" stroke="#3C3C3C" strokeWidth="1.4" strokeLinecap="round" />
  </svg>
);

const FamilyQuestionsIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <path d="M3 4h14a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H11l-4 3v-3H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z" stroke="#3C3C3C" strokeWidth="1.4" strokeLinejoin="round" />
    <line x1="6" y1="8" x2="14" y2="8" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
    <line x1="6" y1="10.5" x2="11" y2="10.5" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
  </svg>
);

const ReflectionIcon: React.FC = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <path d="M5 3h8l3 3v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z" stroke="#3C3C3C" strokeWidth="1.4" strokeLinejoin="round" />
    <path d="M13 3v3h3" stroke="#3C3C3C" strokeWidth="1.4" strokeLinejoin="round" />
    <line x1="7" y1="9" x2="13" y2="9" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
    <line x1="7" y1="12" x2="13" y2="12" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
    <line x1="7" y1="15" x2="10" y2="15" stroke="#3C3C3C" strokeWidth="1.2" strokeLinecap="round" />
  </svg>
);

const SURFACE_ENTRIES: SurfaceEntry[] = [
  {
    surface: 'scripture',
    icon: <ScriptureIcon />,
    label: 'Scripture',
    description: 'Read and reflect on the Word',
  },
  {
    surface: 'prayer',
    icon: <PrayerIcon />,
    label: 'Prayer',
    description: 'Pray, be still, listen',
  },
  {
    surface: 'bereanGuide',
    icon: <BereanGuideIcon />,
    label: 'Berean Guide',
    description: 'Be led through prayer or study',
  },
  {
    surface: 'churchNotes',
    icon: <ChurchNotesIcon />,
    label: 'Church Notes',
    description: 'Capture and review sermon notes',
  },
  {
    surface: 'findChurch',
    icon: <FindChurchIcon />,
    label: 'Find a Church',
    description: 'Find where to worship today',
  },
  {
    surface: 'spaces',
    icon: <SpacesIcon />,
    label: 'Spaces',
    description: 'Connect with your community',
  },
  {
    surface: 'familyQuestions',
    icon: <FamilyQuestionsIcon />,
    label: 'Family Questions',
    description: 'Dinner table conversation starters',
  },
  {
    surface: 'reflection',
    icon: <ReflectionIcon />,
    label: 'Reflection',
    description: 'Journal privately',
  },
];

const SurfaceRow: React.FC<{
  entry: SurfaceEntry;
  onSelect: (surface: SabbathSurface) => void;
}> = ({ entry, onSelect }) => {
  const [hovered, setHovered] = useState(false);

  const rowStyle: React.CSSProperties = {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    padding: '10px 12px',
    borderRadius: SabbathTokens.radiusInner,
    background: hovered ? 'rgba(0,0,0,0.03)' : 'transparent',
    cursor: 'pointer',
    transition: 'background 0.15s ease',
    userSelect: 'none',
    WebkitTapHighlightColor: 'transparent',
  };

  const iconWrapStyle: React.CSSProperties = {
    flexShrink: 0,
    width: '36px',
    height: '36px',
    borderRadius: SabbathTokens.radiusInner,
    background: 'rgba(0,0,0,0.04)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  };

  const labelStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '15px',
    fontWeight: 500,
    color: SabbathTokens.textPrimary,
    lineHeight: '1.2',
    margin: 0,
  };

  const descStyle: React.CSSProperties = {
    fontFamily: SabbathTokens.fontStack,
    fontSize: '13px',
    fontWeight: 400,
    color: SabbathTokens.textTertiary,
    lineHeight: '1.3',
    margin: 0,
  };

  const chevronStyle: React.CSSProperties = {
    marginLeft: 'auto',
    flexShrink: 0,
    color: SabbathTokens.textTertiary,
    opacity: 0.5,
  };

  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`${entry.label}: ${entry.description}`}
      style={rowStyle}
      onClick={() => onSelect(entry.surface)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onSelect(entry.surface);
        }
      }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <div style={iconWrapStyle} aria-hidden="true">
        {entry.icon}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={labelStyle}>{entry.label}</p>
        <p style={descStyle}>{entry.description}</p>
      </div>
      <div style={chevronStyle} aria-hidden="true">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M5 3l4 4-4 4" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
    </div>
  );
};

export const SabbathSurfaceList: React.FC<SabbathSurfaceListProps> = ({
  onSurfaceSelect,
}) => {
  const listStyle: React.CSSProperties = {
    display: 'flex',
    flexDirection: 'column',
    gap: '2px',
  };

  return (
    <nav aria-label="Sabbath surfaces" style={listStyle}>
      {SURFACE_ENTRIES.map((entry) => (
        <SurfaceRow
          key={entry.surface}
          entry={entry}
          onSelect={onSurfaceSelect}
        />
      ))}
    </nav>
  );
};

export default SabbathSurfaceList;
