// === AGENT C: DAILY FEED ===
// BereanFeed.jsx — Standalone Daily Berean Feed module
//
// Props:
//   bereanData     — object from useBereanData() (Agent D contract)
//   onWhySeeingThis — (card) => void  — called when user taps the Info icon on any card
//
// Assumes in scope (no imports):
//   React, useState   — from React
//   Sun, BookOpen, Heart, Users, BookMarked, Star, Feather, Info,
//   ChevronRight, Check, Eye, EyeOff                          — from lucide-react
//   GlassCard, GlassButton, VerseChip, SectionLabel,
//   ArcCardStack, MockBadge                                    — from Agent A primitives
//   tokens (T)                                                 — Agent A design tokens
//
// HARD CONSTRAINTS (override everything):
//   - Crisis prayer items MUST NOT render PrayerFollowUpCard — render CrisisPlaceholderCard instead
//   - Tender items render with <GlassCard tender> and gentle copy — no platitudes
//   - MockBadge on ALL verse text — no exceptions
//   - Every card exposes onWhySeeingThis(card) via Info icon button
//   - Reflections are invitations, not authoritative rulings
//   - No invented Scripture — all verse text via bereanData.getVerse()

// ─── Design Token alias (mirrors Agent A TOKENS) ──────────────────────────────
const T = {
  colors: {
    goldPrimary:    '#C9A84C',
    goldLight:      '#E8CB7A',
    goldDim:        '#8A6F2E',
    bgDeep:         '#0A0A0F',
    bgMid:          '#111118',
    glassFill:      'rgba(255,255,255,0.04)',
    glassBorder:    'rgba(201,168,76,0.18)',
    glassGlow:      'rgba(201,168,76,0.10)',
    textPrimary:    '#F5F0E8',
    textSecondary:  '#B8AFA0',
    textMuted:      '#6B6460',
    crisisRed:      '#D93025',
    crisisRedSoft:  'rgba(217,48,37,0.15)',
    tenderBlue:     '#4A9ECC',
    tenderBlueSoft: 'rgba(74,158,204,0.12)',
    successGreen:   '#3DAA6E',
  },
  blur: { sm: 'blur(8px)', md: 'blur(16px)' },
  radius: { sm: '8px', md: '14px', lg: '20px', xl: '28px', pill: '9999px' },
  spacing: { xs: '4px', sm: '8px', md: '16px', lg: '24px', xl: '40px', xxl: '64px' },
  font: {
    display: "'Cormorant Garamond', Georgia, serif",
    ui: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', system-ui, sans-serif",
  },
  transition: 'all 0.35s cubic-bezier(0.25, 0.46, 0.45, 0.94)',
};

// ─── Local primitives (self-contained so Agent F can drop this file anywhere) ──

function _GlassCard({ children, style, glow = false, elevated = false, danger = false, tender = false }) {
  const borderColor = danger ? T.colors.crisisRed : tender ? T.colors.tenderBlue : T.colors.glassBorder;
  const fillColor   = danger ? T.colors.crisisRedSoft
                    : tender ? T.colors.tenderBlueSoft
                    : elevated ? 'rgba(255,255,255,0.07)'
                    : T.colors.glassFill;
  const boxShadow = [
    `0 0 0 1px ${borderColor}`,
    elevated ? '0 20px 60px rgba(0,0,0,0.55), 0 4px 16px rgba(0,0,0,0.35)'
             : '0 8px 32px rgba(0,0,0,0.40), 0 2px 8px rgba(0,0,0,0.25)',
    glow && !danger && !tender ? `0 0 40px ${T.colors.glassGlow}` : null,
    danger  ? `0 0 32px ${T.colors.crisisRedSoft}`  : null,
    tender  ? `0 0 32px ${T.colors.tenderBlueSoft}` : null,
  ].filter(Boolean).join(', ');
  return (
    <div style={{
      position:             'relative',
      background:           fillColor,
      backdropFilter:       T.blur.md,
      WebkitBackdropFilter: T.blur.md,
      borderRadius:         T.radius.lg,
      boxShadow,
      padding:              T.spacing.lg,
      transition:           T.transition,
      ...style,
    }}>
      {children}
    </div>
  );
}

function _GlassButton({ children, onClick, variant = 'primary', size = 'md', style, disabled = false }) {
  const [hov, setHov] = useState(false);
  const sizeMap = {
    sm: { padding: '6px 14px',  fontSize: '12px', height: '30px' },
    md: { padding: '9px 22px',  fontSize: '14px', height: '40px' },
    lg: { padding: '13px 32px', fontSize: '16px', height: '52px' },
  };
  const vMap = {
    primary: {
      background: hov ? `linear-gradient(135deg,${T.colors.goldLight},${T.colors.goldPrimary})`
                      : `linear-gradient(135deg,${T.colors.goldPrimary},${T.colors.goldDim})`,
      color: T.colors.bgDeep,
      border: `1px solid ${T.colors.goldLight}`,
      fontWeight: '600',
    },
    ghost: {
      background: hov ? 'rgba(255,255,255,0.07)' : T.colors.glassFill,
      color: T.colors.textPrimary,
      border: `1px solid ${T.colors.glassBorder}`,
      fontWeight: '500',
    },
  };
  const v = vMap[variant] ?? vMap.primary;
  const dim = sizeMap[size] ?? sizeMap.md;
  return (
    <button
      onClick={disabled ? undefined : onClick}
      disabled={disabled}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:             'inline-flex',
        alignItems:          'center',
        justifyContent:      'center',
        gap:                 T.spacing.xs,
        borderRadius:        T.radius.pill,
        backdropFilter:      T.blur.sm,
        WebkitBackdropFilter: T.blur.sm,
        fontFamily:          T.font.ui,
        letterSpacing:       '0.02em',
        transition:          T.transition,
        cursor:              disabled ? 'not-allowed' : 'pointer',
        opacity:             disabled ? 0.4 : 1,
        userSelect:          'none',
        whiteSpace:          'nowrap',
        ...dim,
        ...v,
        ...style,
      }}
    >
      {children}
    </button>
  );
}

function _VerseChip({ reference, translation = 'ESV' }) {
  const [hov, setHov] = useState(false);
  return (
    <span
      aria-label={`${reference} ${translation}`}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:             'inline-flex',
        alignItems:          'center',
        gap:                 '4px',
        padding:             '3px 10px',
        borderRadius:        T.radius.pill,
        background:          hov ? 'rgba(201,168,76,0.18)' : 'rgba(201,168,76,0.10)',
        border:              `1px solid ${hov ? T.colors.goldPrimary : T.colors.goldDim}`,
        color:               hov ? T.colors.goldLight : T.colors.goldPrimary,
        fontFamily:          T.font.display,
        fontSize:            '12px',
        fontStyle:           'italic',
        cursor:              'default',
        transition:          T.transition,
        backdropFilter:      T.blur.sm,
        WebkitBackdropFilter: T.blur.sm,
        whiteSpace:          'nowrap',
        userSelect:          'none',
      }}
    >
      {reference}
      <span style={{ opacity: 0.6, fontSize: '10px', fontFamily: T.font.ui, fontStyle: 'normal' }}>
        {translation}
      </span>
    </span>
  );
}

function _SectionLabel({ children, icon, style: overrideStyle }) {
  return (
    <div style={{
      display:       'flex',
      alignItems:    'center',
      gap:           T.spacing.xs,
      fontFamily:    T.font.ui,
      fontSize:      '10px',
      fontWeight:    '700',
      letterSpacing: '0.12em',
      textTransform: 'uppercase',
      color:         T.colors.goldPrimary,
      opacity:       0.85,
      userSelect:    'none',
      ...overrideStyle,
    }}>
      {icon && <span aria-hidden="true" style={{ fontSize: '14px', lineHeight: 1, flexShrink: 0 }}>{icon}</span>}
      <span>{children}</span>
    </div>
  );
}

function _MockBadge() {
  return (
    <span style={{
      display:      'inline-block',
      fontFamily:   T.font.ui,
      fontSize:     '9px',
      color:        T.colors.textMuted,
      background:   'rgba(255,255,255,0.04)',
      border:       '1px solid rgba(255,255,255,0.08)',
      borderRadius: T.radius.sm,
      padding:      '2px 7px',
      lineHeight:   1.4,
    }}>
      Prototype — mock text. Real Scripture from YouVersion license only.
    </span>
  );
}

// Resolve Agent A primitives: prefer injected versions, fall back to locals
// (Agent F can override these by defining GlassCard etc. above this module)
const _Card   = typeof GlassCard    !== 'undefined' ? GlassCard    : _GlassCard;
const _Btn    = typeof GlassButton  !== 'undefined' ? GlassButton  : _GlassButton;
const _Chip   = typeof VerseChip    !== 'undefined' ? VerseChip    : _VerseChip;
const _Label  = typeof SectionLabel !== 'undefined' ? SectionLabel : _SectionLabel;
const _Badge  = typeof MockBadge    !== 'undefined' ? MockBadge    : _MockBadge;

// ─── Shared helpers ────────────────────────────────────────────────────────────

const SEASON_ICONS = {
  'Advent':        '🕯️',
  'Christmas':     '⭐',
  'Epiphany':      '✨',
  'Lent':          '🌿',
  'Holy Week':     '✝️',
  'Easter':        '🌅',
  'Pentecost':     '🔥',
  'Ordinary Time': '🌾',
};

function formatDate(isoStr) {
  if (!isoStr) return '';
  const d = new Date(isoStr);
  return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

function daysSince(isoStr) {
  if (!isoStr) return 0;
  return Math.floor((Date.now() - new Date(isoStr).getTime()) / 86400000);
}

function todayLabel() {
  return new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
}

// ─── Why-button shared component ────────────────────────────────────────────
function WhyButton({ card, onWhySeeingThis }) {
  const [hov, setHov] = useState(false);
  return (
    <button
      aria-label={`Why am I seeing the ${card.type ?? card.cardType} card?`}
      onClick={() => onWhySeeingThis(card)}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        background:   'none',
        border:       'none',
        cursor:       'pointer',
        display:      'flex',
        alignItems:   'center',
        gap:          '4px',
        color:        hov ? T.colors.goldPrimary : T.colors.textMuted,
        fontFamily:   T.font.ui,
        fontSize:     '11px',
        padding:      '3px 6px',
        borderRadius: T.radius.pill,
        transition:   T.transition,
        flexShrink:   0,
      }}
    >
      <Info size={12} aria-hidden="true" />
      Why am I seeing this?
    </button>
  );
}

// ─── Card header row: SectionLabel + WhyButton ────────────────────────────────
function CardHeader({ label, icon, card, onWhySeeingThis, children }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: T.spacing.md, flexWrap: 'wrap', gap: T.spacing.xs }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: T.spacing.sm, flexWrap: 'wrap' }}>
        <_Label icon={icon}>{label}</_Label>
        {children}
      </div>
      <WhyButton card={card} onWhySeeingThis={onWhySeeingThis} />
    </div>
  );
}

// ─── Verse block ──────────────────────────────────────────────────────────────
function VerseBlock({ text, style: overrideStyle }) {
  const clean = (text ?? '').replace(/\[MOCK[^\]]*\]\s*/g, '');
  return (
    <blockquote style={{
      fontFamily:  T.font.display,
      fontSize:    '21px',
      fontStyle:   'italic',
      color:       T.colors.textPrimary,
      lineHeight:  1.58,
      borderLeft:  `3px solid ${T.colors.goldPrimary}`,
      paddingLeft: T.spacing.md,
      margin:      0,
      ...overrideStyle,
    }}>
      {clean}
    </blockquote>
  );
}

// ─── Progress bar ──────────────────────────────────────────────────────────────
function ProgressBar({ pct, label }) {
  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '5px' }}>
        <span style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted }}>{label}</span>
        <span style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.goldPrimary, fontWeight: '600' }}>{pct}%</span>
      </div>
      <div style={{ height: '4px', background: 'rgba(255,255,255,0.08)', borderRadius: '2px', overflow: 'hidden' }}>
        <div style={{
          height:       '100%',
          width:        `${Math.min(100, pct)}%`,
          background:   `linear-gradient(90deg, ${T.colors.goldDim}, ${T.colors.goldPrimary})`,
          borderRadius: '2px',
          transition:   'width 1s ease',
        }} />
      </div>
    </div>
  );
}

// ─── Tender badge ──────────────────────────────────────────────────────────────
function TenderBadge() {
  return (
    <span style={{
      display:      'inline-flex',
      alignItems:   'center',
      gap:          '3px',
      padding:      '2px 9px',
      borderRadius: T.radius.pill,
      background:   T.colors.tenderBlueSoft,
      border:       `1px solid rgba(74,158,204,0.25)`,
      fontFamily:   T.font.ui,
      fontSize:     '10px',
      color:        T.colors.tenderBlue,
      fontWeight:   '500',
      letterSpacing:'0.05em',
    }}>
      🕊 Gentle
    </span>
  );
}

// ─── CARD 1: VerseReflectionCard ─────────────────────────────────────────────
function VerseReflectionCard({ card, bereanData, onWhySeeingThis }) {
  const { readingPlan, user, getVerse } = bereanData;
  const verse = getVerse(readingPlan.todayPassageRef, user.translationPref);
  return (
    <_Card glow elevated>
      <CardHeader label="Daily Verse" icon={<Sun size={12} />} card={card} onWhySeeingThis={onWhySeeingThis} />

      <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted, marginBottom: T.spacing.sm, letterSpacing: '0.06em' }}>
        {readingPlan.todayPassageRef}
      </p>

      <VerseBlock text={verse.text} style={{ marginBottom: T.spacing.sm }} />

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: T.spacing.xs, alignItems: 'center', marginBottom: T.spacing.lg }}>
        <_Chip reference={readingPlan.todayPassageRef} translation={user.translationPref} />
        <_Badge />
      </div>

      {/* Reflection — invitation only, never doctrinal ruling */}
      <div style={{
        background:   T.colors.glassFill,
        borderRadius: T.radius.md,
        padding:      T.spacing.md,
        border:       `1px solid ${T.colors.glassBorder}`,
      }}>
        <_Label style={{ marginBottom: '8px' }}>
          <Feather size={10} style={{ marginRight: '4px' }} aria-hidden="true" />
          A moment to consider
        </_Label>
        <p style={{ fontFamily: T.font.display, fontSize: '16px', color: T.colors.textSecondary, lineHeight: 1.65, marginBottom: '8px' }}>
          What does it look like to seek first today — before the list, the inbox, the plans?
          Not as a task to accomplish, but as an orientation of the heart.
          Where does your attention naturally go first in the morning?
        </p>
        <p style={{ fontFamily: T.font.ui, fontSize: '10px', color: T.colors.textMuted, lineHeight: 1.5 }}>
          This reflection is an invitation, not instruction. It represents no doctrinal position.
        </p>
      </div>
    </_Card>
  );
}

// ─── CARD 2: ReadingPlanCard ──────────────────────────────────────────────────
function ReadingPlanCard({ card, bereanData, onWhySeeingThis }) {
  const { readingPlan } = bereanData;
  const pct = Math.round(readingPlan.progress * 100);
  const remaining = readingPlan.totalDays - readingPlan.currentDay;
  return (
    <_Card>
      <CardHeader label="Reading Plan" icon={<BookOpen size={12} />} card={card} onWhySeeingThis={onWhySeeingThis} />

      <p style={{ fontFamily: T.font.display, fontSize: '22px', color: T.colors.textPrimary, marginBottom: T.spacing.xs }}>
        {readingPlan.name}
      </p>
      <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.colors.textSecondary, marginBottom: T.spacing.lg }}>
        Day {readingPlan.currentDay} of {readingPlan.totalDays}
        {remaining > 0 ? ` · ${remaining} days remaining` : ' · Complete!'}
      </p>

      <div style={{ marginBottom: T.spacing.lg }}>
        <ProgressBar pct={pct} label={`${pct}% complete`} />
      </div>

      <div style={{
        display:        'flex',
        alignItems:     'center',
        justifyContent: 'space-between',
        background:     T.colors.glassFill,
        borderRadius:   T.radius.md,
        padding:        T.spacing.md,
        border:         `1px solid ${T.colors.glassBorder}`,
      }}>
        <div>
          <p style={{ fontFamily: T.font.ui, fontSize: '10px', color: T.colors.textMuted, marginBottom: '4px' }}>Today's reading</p>
          <_Chip reference={readingPlan.todayPassageRef} />
        </div>
        <_Btn variant="ghost" size="sm" style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          Read Now <ChevronRight size={12} aria-hidden="true" />
        </_Btn>
      </div>
    </_Card>
  );
}

// ─── Crisis placeholder (Agent E provides the real CrisisCard; this is the fallback) ─
function CrisisPlaceholderCard({ item }) {
  return (
    <_Card danger>
      <_Label icon="🛡️" style={{ marginBottom: T.spacing.md }}>You're Not Alone</_Label>
      <p style={{ fontFamily: T.font.display, fontSize: '18px', color: T.colors.textPrimary, lineHeight: 1.55, marginBottom: T.spacing.md }}>
        You've been carrying something heavy. Berean can't carry it with you — but people can.
      </p>
      <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.colors.textSecondary, lineHeight: 1.7, marginBottom: T.spacing.lg }}>
        Please reach out to someone who loves you — your pastor, a trusted friend, or a counselor.
        You don't have to be alone in this.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: T.spacing.sm, marginBottom: T.spacing.md }}>
        {[
          { title: '988 Suicide & Crisis Lifeline', sub: 'Call or text 988 (US)', href: 'tel:988' },
          { title: 'Crisis Text Line',              sub: 'Text HOME to 741741',    href: 'sms:741741?body=HOME' },
        ].map(r => (
          <a key={r.href} href={r.href} aria-label={r.title} style={{
            display:        'block',
            padding:        '10px 14px',
            background:     'rgba(217,48,37,0.08)',
            borderRadius:   T.radius.md,
            border:         '1px solid rgba(217,48,37,0.2)',
            textDecoration: 'none',
          }}>
            <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.colors.textPrimary, fontWeight: '600', marginBottom: '2px' }}>{r.title}</p>
            <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted }}>{r.sub}</p>
          </a>
        ))}
      </div>
      {/* Verse anchor — MOCK-LABELED. NOT AI-generated. */}
      <blockquote style={{
        fontFamily: T.font.display, fontSize: '16px', fontStyle: 'italic',
        color: T.colors.goldLight, lineHeight: 1.55,
        borderLeft: `3px solid ${T.colors.goldDim}`, paddingLeft: T.spacing.md, marginTop: T.spacing.md,
      }}>
        "Cast all your anxiety on him because he cares for you."
      </blockquote>
      <div style={{ marginTop: '6px', display: 'flex', flexWrap: 'wrap', gap: T.spacing.xs, alignItems: 'center' }}>
        <_Chip reference="1 Peter 5:7" translation="NIV" />
        <_Badge />
      </div>
    </_Card>
  );
}

// ─── CARD 3: PrayerFollowUpCard ───────────────────────────────────────────────
// SAFETY GATE: crisis items → CrisisPlaceholderCard (or Agent E's renderSafetyCard)
function PrayerFollowUpCard({ card, bereanData, onWhySeeingThis, renderSafetyCard }) {
  const { prayerList } = bereanData;
  const [action, setAction] = useState(null);

  // Pick the first eligible normal/tender prayer item
  const eligible = (prayerList ?? [])
    .filter(p => p.status === 'active' && p.sensitivity !== 'crisis')
    .sort((a, b) => new Date(a.prayedOn) - new Date(b.prayedOn));

  if (eligible.length === 0) return null;
  const prayer = eligible[0];

  // Tender items render through this card with tender GlassCard variant
  const isTender = prayer.sensitivity === 'tender';

  return (
    <_Card tender={isTender}>
      <CardHeader label="Prayer Follow-up" icon={<Heart size={12} />} card={card} onWhySeeingThis={onWhySeeingThis}>
        {isTender && <TenderBadge />}
      </CardHeader>

      <p style={{ fontFamily: T.font.display, fontSize: '22px', color: T.colors.textPrimary, lineHeight: 1.4, marginBottom: T.spacing.xs }}>
        {prayer.subject}
      </p>
      <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.colors.textSecondary, marginBottom: T.spacing.md }}>
        You prayed for <strong style={{ color: T.colors.textPrimary }}>{prayer.forWhom}</strong> on {formatDate(prayer.prayedOn)}
        {daysSince(prayer.prayedOn) > 0 ? ` · ${daysSince(prayer.prayedOn)} day${daysSince(prayer.prayedOn) === 1 ? '' : 's'} ago` : ' · today'}
      </p>

      {isTender && (
        <div style={{
          fontFamily:   T.font.ui,
          fontSize:     '12px',
          color:        T.colors.tenderBlue,
          background:   T.colors.tenderBlueSoft,
          borderRadius: T.radius.md,
          padding:      '10px 14px',
          marginBottom: T.spacing.md,
          lineHeight:   1.65,
          border:       `1px solid rgba(74,158,204,0.18)`,
        }}>
          Berean is holding this gently. Consider reaching out to {prayer.forWhom},
          or sharing with your pastor or a trusted friend in community.
        </div>
      )}

      {!action ? (
        <div style={{ display: 'flex', gap: T.spacing.sm, flexWrap: 'wrap' }}>
          <_Btn size="sm" variant="primary" onClick={() => setAction('prayed')}
            style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Heart size={11} aria-hidden="true" /> Pray Again
          </_Btn>
          <_Btn size="sm" variant="ghost" onClick={() => setAction('answered')}
            style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Check size={11} aria-hidden="true" /> Mark Answered
          </_Btn>
          <_Btn size="sm" variant="ghost" onClick={() => setAction('checkin')}
            style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            <ChevronRight size={11} aria-hidden="true" /> Check In
          </_Btn>
        </div>
      ) : (
        <div style={{
          padding: T.spacing.md,
          background: 'rgba(61,170,110,0.10)',
          border: `1px solid rgba(61,170,110,0.25)`,
          borderRadius: T.radius.md,
        }}>
          <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.colors.successGreen }}>
            {action === 'prayed'   && '✓ Marked as prayed today.'}
            {action === 'answered' && '✓ Celebrated as answered. Glory be.'}
            {action === 'checkin'  && '✓ Reminder to check in has been noted.'}
          </p>
        </div>
      )}
    </_Card>
  );
}

// ─── CARD 4: SanctuaryStirringCard ───────────────────────────────────────────
function SanctuaryStirringCard({ card, bereanData, onWhySeeingThis }) {
  const { sanctuaries } = bereanData;
  const s = sanctuaries?.[0];
  if (!s) return null;
  return (
    <_Card>
      <CardHeader label="Sanctuary Stirring" icon={<Users size={12} />} card={card} onWhySeeingThis={onWhySeeingThis} />

      <p style={{ fontFamily: T.font.display, fontSize: '22px', color: T.colors.textPrimary, marginBottom: T.spacing.xs }}>
        {s.name}
      </p>
      {s.recentActivity && (
        <p style={{ fontFamily: T.font.display, fontSize: '14px', fontStyle: 'italic', color: T.colors.textSecondary, marginBottom: T.spacing.lg }}>
          "{s.recentActivity}"
        </p>
      )}

      <div style={{ display: 'flex', gap: T.spacing.md, marginBottom: T.spacing.lg }}>
        {[
          { label: 'Open prayer requests', value: s.openPrayerRequests },
          { label: 'Active threads',       value: s.activeThreads },
        ].map(stat => (
          <div key={stat.label} style={{
            flex: 1, textAlign: 'center',
            background: T.colors.glassFill, borderRadius: T.radius.md,
            padding: T.spacing.md, border: `1px solid ${T.colors.glassBorder}`,
          }}>
            <p style={{ fontFamily: T.font.display, fontSize: '30px', color: T.colors.goldLight, fontWeight: 500, lineHeight: 1 }}>
              {stat.value}
            </p>
            <p style={{ fontFamily: T.font.ui, fontSize: '10px', color: T.colors.textMuted, marginTop: '4px' }}>
              {stat.label}
            </p>
          </div>
        ))}
      </div>

      <_Btn variant="ghost" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
        <Heart size={13} aria-hidden="true" /> Encourage someone
      </_Btn>
    </_Card>
  );
}

// ─── CARD 5: OpenStudyCard ────────────────────────────────────────────────────
function OpenStudyCard({ card, bereanData, onWhySeeingThis }) {
  const { highlights, user, getVerse } = bereanData;
  const h = highlights?.[0];
  if (!h) return null;
  const verse = getVerse(h.verseRef, user.translationPref);
  return (
    <_Card>
      <CardHeader label="Open Study" icon={<BookMarked size={12} />} card={card} onWhySeeingThis={onWhySeeingThis} />

      <VerseBlock text={verse.text} style={{ marginBottom: T.spacing.sm }} />
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: T.spacing.xs, alignItems: 'center', marginBottom: T.spacing.lg }}>
        <_Chip reference={h.verseRef} translation={user.translationPref} />
        <_Badge />
      </div>

      {h.note && (
        <div style={{
          background: T.colors.glassFill, borderRadius: T.radius.md,
          padding: T.spacing.md, border: `1px solid ${T.colors.glassBorder}`,
          marginBottom: T.spacing.lg,
        }}>
          <p style={{ fontFamily: T.font.ui, fontSize: '10px', color: T.colors.textMuted, marginBottom: '5px' }}>
            Your note · saved {formatDate(h.savedOn)}
          </p>
          <p style={{ fontFamily: T.font.display, fontSize: '15px', fontStyle: 'italic', color: T.colors.textSecondary, lineHeight: 1.65 }}>
            "{h.note}"
          </p>
        </div>
      )}

      <_Btn variant="ghost" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
        <ChevronRight size={13} aria-hidden="true" /> Continue studying
      </_Btn>
    </_Card>
  );
}

// ─── CARD 6: MemoryVerseCard ──────────────────────────────────────────────────
function MemoryVerseCard({ card, bereanData, onWhySeeingThis }) {
  const { memoryVerses, user, getVerse } = bereanData;
  const [revealed, setRevealed] = useState(false);

  // Pick SRS-due verse with lowest strength
  const today = new Date().toISOString().slice(0, 10);
  const due = (memoryVerses ?? [])
    .filter(v => v.srsDueDate <= today)
    .sort((a, b) => a.strength - b.strength)[0];

  if (!due) return null;

  const verse = getVerse(due.verseRef, user.translationPref);
  const pct   = Math.round(due.strength * 100);

  return (
    <_Card>
      <CardHeader label="Memory Verse" icon={<Star size={12} />} card={card} onWhySeeingThis={onWhySeeingThis}>
        {due.streak > 0 && (
          <span style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted }}>
            🔥 {due.streak}-day streak
          </span>
        )}
      </CardHeader>

      <p style={{ fontFamily: T.font.display, fontSize: '20px', color: T.colors.textPrimary, marginBottom: T.spacing.md }}>
        {due.verseRef}
      </p>

      <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted, marginBottom: T.spacing.sm }}>
        Last practiced {due.srsDueDate ? formatDate(due.srsDueDate) : '—'}
      </p>

      <div style={{ marginBottom: T.spacing.lg }}>
        <ProgressBar pct={pct} label="Memory strength" />
      </div>

      {!revealed ? (
        <>
          <p style={{ fontFamily: T.font.display, fontSize: '16px', fontStyle: 'italic', color: T.colors.textSecondary, marginBottom: T.spacing.md, lineHeight: 1.6 }}>
            How does it start? Take a moment to recall before revealing.
          </p>
          <_Btn variant="primary" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}
            onClick={() => setRevealed(true)}>
            <Eye size={13} aria-hidden="true" /> Reveal verse
          </_Btn>
        </>
      ) : (
        <>
          <VerseBlock text={verse.text} style={{ marginBottom: T.spacing.sm }} />
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: T.spacing.xs, alignItems: 'center', marginBottom: T.spacing.lg }}>
            <_Chip reference={due.verseRef} translation={user.translationPref} />
            <_Badge />
          </div>
          <div style={{ display: 'flex', gap: T.spacing.sm }}>
            <_Btn size="sm" variant="primary" style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px' }}>
              <Check size={11} aria-hidden="true" /> I remembered it
            </_Btn>
            <_Btn size="sm" variant="ghost" style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px' }}
              onClick={() => setRevealed(false)}>
              <EyeOff size={11} aria-hidden="true" /> Practice again
            </_Btn>
          </div>
        </>
      )}
    </_Card>
  );
}

// ─── CARD 7: SeasonalRhythmCard ───────────────────────────────────────────────
function SeasonalRhythmCard({ card, bereanData, onWhySeeingThis }) {
  const { seasonal } = bereanData;
  if (!seasonal || seasonal.liturgicalSeason === null || seasonal.liturgicalSeason === undefined) return null;

  const seasonIcon = SEASON_ICONS[seasonal.liturgicalSeason] ?? '🌾';

  return (
    <_Card glow>
      <CardHeader label="Seasonal Rhythm" icon={seasonIcon} card={card} onWhySeeingThis={onWhySeeingThis} />

      <div style={{ marginBottom: T.spacing.md }}>
        <span style={{
          display:       'inline-flex',
          alignItems:    'center',
          gap:           '6px',
          padding:       '4px 14px',
          background:    'rgba(201,168,76,0.08)',
          border:        `1px solid ${T.colors.goldDim}`,
          borderRadius:  T.radius.pill,
          fontFamily:    T.font.ui,
          fontSize:      '11px',
          color:         T.colors.goldLight,
          letterSpacing: '0.07em',
          fontWeight:    '500',
        }}>
          <span aria-hidden="true">{seasonIcon}</span>
          {seasonal.liturgicalSeason}
        </span>
      </div>

      <p style={{
        fontFamily:  T.font.display,
        fontSize:    '21px',
        fontStyle:   'italic',
        color:       T.colors.textPrimary,
        lineHeight:  1.6,
        borderLeft:  `3px solid ${T.colors.goldDim}`,
        paddingLeft: T.spacing.md,
      }}>
        "{seasonal.prompt}"
      </p>
    </_Card>
  );
}

// ─── Empty / Preparing / Ready state screens ──────────────────────────────────

function PreparingState() {
  return (
    <div style={{
      minHeight:      '100vh',
      display:        'flex',
      flexDirection:  'column',
      alignItems:     'center',
      justifyContent: 'center',
      background:     `linear-gradient(160deg, ${T.colors.bgDeep}, ${T.colors.bgMid})`,
      padding:        T.spacing.xl,
      textAlign:      'center',
    }}>
      {/* Pulsing gold orb */}
      <div style={{
        width:        '72px',
        height:       '72px',
        borderRadius: '50%',
        background:   `radial-gradient(circle at 38% 38%, ${T.colors.goldLight}, ${T.colors.goldDim})`,
        boxShadow:    `0 0 48px ${T.colors.glassGlow}, 0 0 0 1px ${T.colors.glassBorder}`,
        marginBottom: T.spacing.xl,
        animation:    'berean-breathe 2.2s ease-in-out infinite',
        display:      'flex',
        alignItems:   'center',
        justifyContent: 'center',
        fontSize:     '28px',
      }}>
        ✦
      </div>
      <style>{`
        @keyframes berean-breathe {
          0%,100% { transform: scale(1);    opacity: 0.75; }
          50%      { transform: scale(1.18); opacity: 1;    }
        }
      `}</style>
      <h2 style={{ fontFamily: T.font.display, fontSize: '30px', fontWeight: 300, color: T.colors.goldLight, marginBottom: T.spacing.md, lineHeight: 1.3 }}>
        Your Berean is being prepared.
      </h2>
      <p style={{ fontFamily: T.font.ui, fontSize: '14px', color: T.colors.textSecondary, lineHeight: 1.75, maxWidth: '320px' }}>
        Check back in the morning — formation takes overnight.
        Berean reads where you are in your walk and prepares a personal arc of reflection.
      </p>
      <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted, marginTop: T.spacing.lg, fontStyle: 'italic' }}>
        Formation over information. Faithfulness over productivity.
      </p>
    </div>
  );
}

function EmptyState() {
  return (
    <div style={{
      minHeight:      '100vh',
      display:        'flex',
      flexDirection:  'column',
      alignItems:     'center',
      justifyContent: 'center',
      background:     `linear-gradient(160deg, ${T.colors.bgDeep}, ${T.colors.bgMid})`,
      padding:        T.spacing.xl,
      textAlign:      'center',
    }}>
      <div style={{
        width:        '56px',
        height:       '56px',
        borderRadius: '50%',
        background:   `radial-gradient(circle at 38% 38%, ${T.colors.goldPrimary}, ${T.colors.goldDim})`,
        boxShadow:    `0 0 32px ${T.colors.glassGlow}`,
        marginBottom: T.spacing.lg,
        display:      'flex',
        alignItems:   'center',
        justifyContent: 'center',
        fontSize:     '22px',
        animation:    'berean-breathe 3s ease-in-out infinite',
      }}>
        ✦
      </div>
      <style>{`
        @keyframes berean-breathe {
          0%,100% { transform: scale(1);    opacity: 0.75; }
          50%      { transform: scale(1.18); opacity: 1;    }
        }
      `}</style>
      <p style={{ fontFamily: T.font.display, fontSize: '26px', fontWeight: 300, color: T.colors.textPrimary, lineHeight: 1.5, marginBottom: T.spacing.sm }}>
        Your Berean is being prepared.
      </p>
      <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.colors.textMuted, lineHeight: 1.7, maxWidth: '300px' }}>
        Check back in the morning — formation takes overnight.
      </p>
    </div>
  );
}

// ─── Arc card stack (local — avoids dependency on Agent A's ArcCardStack) ──────
function LocalArcCardStack({ cards = [], activeIndex = 0, onSelect }) {
  const FAN_ROTATE    = 6;
  const FAN_TX        = 44;
  const FAN_SCALE     = 0.07;
  const VISIBLE_RANGE = 2;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: T.spacing.md }}>
      <div
        role="listbox"
        aria-label="Today's arc card stack"
        style={{ position: 'relative', width: '280px', height: '320px', userSelect: 'none' }}
      >
        {cards.map((card, idx) => {
          const offset   = idx - activeIndex;
          const absOff   = Math.abs(offset);
          const sign     = Math.sign(offset);
          const isActive = offset === 0;
          if (absOff > VISIBLE_RANGE) return null;

          const rotate     = sign * FAN_ROTATE * absOff;
          const translateX = sign * FAN_TX * absOff;
          const scale      = 1 - FAN_SCALE * absOff;
          const zIndex     = 10 - absOff;
          const opacity    = 1 - 0.18 * absOff;

          return (
            <div
              key={card.id ?? idx}
              role="option"
              aria-selected={isActive}
              aria-label={`Card ${idx + 1} of ${cards.length}: ${card.type ?? card.cardType}`}
              tabIndex={0}
              onClick={() => !isActive && onSelect?.(idx)}
              onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') onSelect?.(idx); }}
              style={{
                position:             'absolute',
                top:                  0,
                left:                 '50%',
                width:                '240px',
                marginLeft:           '-120px',
                height:               '100%',
                background:           isActive
                  ? 'linear-gradient(160deg,rgba(255,255,255,0.09) 0%,rgba(255,255,255,0.04) 100%)'
                  : T.colors.glassFill,
                backdropFilter:       T.blur.md,
                WebkitBackdropFilter: T.blur.md,
                borderRadius:         T.radius.xl,
                border:               `1px solid ${isActive ? T.colors.glassBorder : 'rgba(201,168,76,0.08)'}`,
                boxShadow:            isActive
                  ? `0 0 0 1px ${T.colors.glassBorder}, 0 24px 64px rgba(0,0,0,0.55), 0 0 32px ${T.colors.glassGlow}`
                  : '0 8px 24px rgba(0,0,0,0.35)',
                transform:            `translateX(${translateX}px) rotate(${rotate}deg) scale(${scale})`,
                transformOrigin:      'center bottom',
                zIndex,
                opacity,
                cursor:               isActive ? 'default' : 'pointer',
                transition:           T.transition,
                padding:              T.spacing.lg,
                display:              'flex',
                flexDirection:        'column',
                gap:                  T.spacing.sm,
                overflow:             'hidden',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: T.spacing.sm }}>
                <span aria-hidden="true" style={{ fontSize: '18px', lineHeight: 1, filter: isActive ? 'none' : 'brightness(0.7)' }}>
                  {card.icon ?? '✦'}
                </span>
                <_Label style={{ opacity: isActive ? 0.85 : 0.5 }}>{card.type ?? card.cardType}</_Label>
              </div>
              {card.preview && (
                <p style={{
                  fontFamily:      T.font.display,
                  fontSize:        '13px',
                  fontStyle:       'italic',
                  color:           isActive ? T.colors.textPrimary : T.colors.textSecondary,
                  lineHeight:      1.55,
                  flex:            1,
                  overflow:        'hidden',
                  display:         '-webkit-box',
                  WebkitLineClamp: 5,
                  WebkitBoxOrient:'vertical',
                  transition:      T.transition,
                }}>
                  {card.preview}
                </p>
              )}
              {card.chips?.length > 0 && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: T.spacing.xs, marginTop: 'auto' }}>
                  {card.chips.map((c, ci) => (
                    <_Chip key={ci} reference={c.ref} translation={c.tr ?? 'ESV'} />
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Dot navigation */}
      <div role="tablist" aria-label="Arc card navigation" style={{ display: 'flex', gap: T.spacing.sm, alignItems: 'center' }}>
        {cards.map((card, idx) => {
          const isActive = idx === activeIndex;
          return (
            <button
              key={card.id ?? idx}
              role="tab"
              aria-selected={isActive}
              aria-label={`Card ${idx + 1}`}
              onClick={() => onSelect?.(idx)}
              style={{
                width:        isActive ? '20px' : '6px',
                height:       '6px',
                borderRadius: T.radius.pill,
                background:   isActive ? T.colors.goldPrimary : T.colors.textMuted,
                border:       'none',
                padding:      0,
                cursor:       'pointer',
                transition:   T.transition,
                boxShadow:    isActive ? `0 0 8px ${T.colors.goldDim}` : 'none',
                flexShrink:   0,
              }}
            />
          );
        })}
      </div>
    </div>
  );
}

// Resolve: prefer Agent A's ArcCardStack if available
const _ArcStack = typeof ArcCardStack !== 'undefined' ? ArcCardStack : LocalArcCardStack;

// ─── CARD REGISTRY ────────────────────────────────────────────────────────────
// Maps cardType string → renderer component
const CARD_RENDERERS = {
  verse:     VerseReflectionCard,
  plan:      ReadingPlanCard,
  prayer:    PrayerFollowUpCard,
  sanctuary: SanctuaryStirringCard,
  study:     OpenStudyCard,
  memory:    MemoryVerseCard,
  seasonal:  SeasonalRhythmCard,
};

// ─── MAIN EXPORT: BereanFeed ──────────────────────────────────────────────────

export const BereanFeed = ({ bereanData, onWhySeeingThis }) => {
  const [arcIndex, setArcIndex] = useState(0);

  // status comes from bereanData; default 'ready' if not provided
  const status = bereanData?.status ?? 'ready';

  // Route non-ready states immediately
  if (status === 'preparing') return <PreparingState />;
  if (status === 'empty')     return <EmptyState />;

  const {
    user,
    readingPlan,
    prayerList = [],
    sanctuaries = [],
    highlights = [],
    memoryVerses = [],
    seasonal,
    dailyCards = [],
    whySeeingThis,
  } = bereanData;

  // Build arc card list from dailyCards (Agent D's assembled output)
  // Filter crisis items out of the arc; they render in a dedicated section below
  const arcCards = dailyCards.filter(c => {
    if (c.cardType === 'prayer') {
      const p = prayerList.find(p => c.id?.includes(p.id));
      if (p && p.sensitivity === 'crisis') return false;
    }
    return true;
  });

  // Identify active crisis items (never in arc, always rendered separately)
  const crisisItems = prayerList.filter(p => p.sensitivity === 'crisis' && p.status === 'active');

  // If dailyCards is empty, build a minimal set so the feed isn't blank
  const feedCards = dailyCards.length > 0 ? dailyCards : [
    { id: 'fb-verse',    cardType: 'verse',    type: 'Daily Verse',        icon: '✦',  preview: readingPlan?.todayPassageRef ?? '', chips: [] },
    { id: 'fb-plan',     cardType: 'plan',     type: 'Reading Plan',       icon: '📖', preview: readingPlan?.name ?? '',            chips: [] },
    { id: 'fb-prayer',   cardType: 'prayer',   type: 'Prayer Follow-up',   icon: '🙏', preview: '',                                chips: [] },
    { id: 'fb-sanct',    cardType: 'sanctuary',type: 'Sanctuary Stirring',  icon: '⛪', preview: sanctuaries[0]?.name ?? '',        chips: [] },
    { id: 'fb-study',    cardType: 'study',    type: 'Open Study',         icon: '🔍', preview: highlights[0]?.note ?? '',         chips: [] },
    { id: 'fb-memory',   cardType: 'memory',   type: 'Memory Verse',       icon: '⭐', preview: memoryVerses[0]?.verseRef ?? '',   chips: [] },
    ...(seasonal?.liturgicalSeason
      ? [{ id: 'fb-seasonal', cardType: 'seasonal', type: 'Seasonal Rhythm', icon: '🌾', preview: seasonal.prompt ?? '', chips: [] }]
      : []),
  ];

  const arcSource = dailyCards.length > 0 ? arcCards : feedCards.filter(c => c.cardType !== 'prayer' || !crisisItems.length);

  const handleWhySeeingThis = (card) => {
    if (onWhySeeingThis) {
      // Enrich card with whySeeingThis explanation so caller can display it
      const explanation = typeof whySeeingThis === 'function' ? whySeeingThis(card) : null;
      onWhySeeingThis({ ...card, whyExplanation: explanation });
    }
  };

  return (
    <div style={{
      minHeight:  '100vh',
      background: `linear-gradient(160deg, ${T.colors.bgDeep} 0%, ${T.colors.bgMid} 100%)`,
      padding:    `0 ${T.spacing.md} ${T.spacing.xxl}`,
      overflowX:  'hidden',
    }}>
      <div style={{ maxWidth: '480px', margin: '0 auto', width: '100%' }}>

        {/* ── Header ──────────────────────────────────────────────── */}
        <div style={{
          padding:        `${T.spacing.xl} 0 ${T.spacing.lg}`,
          display:        'flex',
          justifyContent: 'space-between',
          alignItems:     'flex-end',
        }}>
          <div>
            <_Label icon={<Sun size={11} />} style={{ marginBottom: '6px' }}>Berean</_Label>
            <h1 style={{
              fontFamily:  T.font.display,
              fontSize:    '32px',
              fontWeight:  300,
              color:       T.colors.textPrimary,
              lineHeight:  1.2,
              marginBottom:'2px',
            }}>
              Good morning, {user?.name ?? 'friend'}.
            </h1>

            {/* Date + liturgical season label */}
            <p style={{ fontFamily: T.font.ui, fontSize: '12px', color: T.colors.textMuted, marginTop: '4px', display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
              <span>{todayLabel()}</span>
              {seasonal?.liturgicalSeason && (
                <>
                  <span style={{ opacity: 0.4 }}>·</span>
                  <span style={{
                    display:      'inline-flex',
                    alignItems:   'center',
                    gap:          '3px',
                    color:        T.colors.goldPrimary,
                    fontStyle:    'italic',
                  }}>
                    <span aria-hidden="true">{SEASON_ICONS[seasonal.liturgicalSeason] ?? '🌾'}</span>
                    {seasonal.liturgicalSeason}
                  </span>
                </>
              )}
              <span style={{ opacity: 0.4 }}>·</span>
              <span>{feedCards.length} card{feedCards.length !== 1 ? 's' : ''} ready</span>
            </p>
          </div>

          {/* Berean emblem */}
          <div style={{
            width:          '44px',
            height:         '44px',
            borderRadius:   '50%',
            background:     `radial-gradient(circle at 38% 38%, ${T.colors.goldPrimary}, ${T.colors.goldDim})`,
            display:        'flex',
            alignItems:     'center',
            justifyContent: 'center',
            fontSize:       '18px',
            flexShrink:     0,
            boxShadow:      `0 0 28px ${T.colors.glassGlow}, 0 0 0 1px ${T.colors.glassBorder}`,
          }}
            aria-hidden="true"
          >
            ✦
          </div>
        </div>

        {/* ── Arc card stack (~50% viewport height) ────────────────── */}
        <div style={{ minHeight: '45vh', display: 'flex', flexDirection: 'column', justifyContent: 'center', marginBottom: T.spacing.xl }}>
          {arcSource.length > 0
            ? <_ArcStack cards={arcSource} activeIndex={arcIndex} onSelect={setArcIndex} />
            : (
              <div style={{ textAlign: 'center', padding: T.spacing.xl }}>
                <p style={{ fontFamily: T.font.display, fontSize: '20px', color: T.colors.textMuted, fontStyle: 'italic' }}>
                  Your arc is taking shape.
                </p>
              </div>
            )
          }
        </div>

        {/* ── Scrollable card list ─────────────────────────────────── */}
        <div style={{
          display:        'flex',
          justifyContent: 'space-between',
          alignItems:     'center',
          marginBottom:   T.spacing.md,
        }}>
          <_Label>Today's Arc</_Label>
          <span style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted }}>
            {feedCards.length} cards
          </span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: T.spacing.md }}>
          {feedCards.map((card) => {
            // Crisis prayer items route to safety card — never PrayerFollowUpCard
            if (card.cardType === 'prayer') {
              const matchedPrayer = prayerList.find(p => card.id?.includes(p.id));
              if (matchedPrayer?.sensitivity === 'crisis') {
                return (
                  <CrisisPlaceholderCard key={card.id} item={matchedPrayer} />
                );
              }
            }

            const Renderer = CARD_RENDERERS[card.cardType];
            if (!Renderer) return null;

            return (
              <Renderer
                key={card.id}
                card={card}
                bereanData={bereanData}
                onWhySeeingThis={handleWhySeeingThis}
              />
            );
          })}
        </div>

        {/* ── Crisis section — always separate, always below feed ───── */}
        {crisisItems.length > 0 && (
          <div style={{ marginTop: T.spacing.xl }}>
            <_Label icon="🛡️" style={{ marginBottom: T.spacing.md }}>A note on something heavy</_Label>
            {crisisItems.map(prayer => (
              <CrisisPlaceholderCard key={prayer.id} item={prayer} />
            ))}
          </div>
        )}

        {/* ── Footer ──────────────────────────────────────────────── */}
        <div style={{ paddingTop: T.spacing.xl, textAlign: 'center' }}>
          <p style={{
            fontFamily: T.font.display,
            fontSize:   '13px',
            fontStyle:  'italic',
            color:      T.colors.textMuted,
            lineHeight: 1.65,
            marginBottom: '6px',
          }}>
            Berean prepared this briefing overnight.
          </p>
          <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.colors.textMuted, opacity: 0.6 }}>
            Formation over information. Faithfulness over productivity.
          </p>
        </div>

      </div>
    </div>
  );
};

// === END AGENT C: DAILY FEED ===
