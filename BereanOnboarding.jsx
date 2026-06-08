// === AGENT B: ONBOARDING ===
// BereanOnboarding.jsx — 5-screen first-run flow for the Berean daily formation companion
//
// Assumes in scope: React, useState (from 'react'), and lucide-react icons:
//   BookOpen, Users, Heart, ChevronRight, Bell, Check, Sparkles
//
// Design tokens contract (from Agent A):
//   tokens.gold, tokens.goldLight, tokens.goldDim
//   tokens.glassLight, tokens.glassDark, tokens.glassBorder, tokens.glassGlow
//   tokens.bgDeep, tokens.textPrimary, tokens.textSecondary, tokens.textMuted
//   tokens.spacing.{xs,sm,md,lg,xl}
//   tokens.radius.{card,pill,lg,xl}
//   tokens.blur.{sm,card}
//   tokens.font.{display,ui}
//   tokens.transition
//   Components: GlassCard, GlassButton, SectionLabel — used by name
//
// Safety rules enforced:
//   - No localStorage / sessionStorage — React state only
//   - All integrations default OFF
//   - No dark patterns — no "skip = you miss out" framing
//
// Props: <BereanOnboarding onComplete={() => void} />
// onComplete is called with { selectedTopics: string[], integrations: object, notificationTime: string }

const tokens = {
  gold:        '#C9A84C',
  goldLight:   '#E8CB7A',
  goldDim:     '#8A6F2E',
  glassLight:  'rgba(255,255,255,0.07)',
  glassDark:   'rgba(255,255,255,0.04)',
  glassBorder: 'rgba(201,168,76,0.18)',
  glassGlow:   'rgba(201,168,76,0.10)',
  bgDeep:      '#0A0A0F',
  textPrimary: '#F5F0E8',
  textSecondary:'#B8AFA0',
  textMuted:   '#6B6460',
  spacing: { xs: '4px', sm: '8px', md: '16px', lg: '24px', xl: '40px' },
  radius:  { card: '20px', pill: '9999px', lg: '20px', xl: '28px' },
  blur:    { sm: 'blur(8px)', card: 'blur(16px)' },
  font: {
    display: "'Cormorant Garamond', Georgia, serif",
    ui:      "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif",
  },
  transition: 'all 0.35s cubic-bezier(0.25, 0.46, 0.45, 0.94)',
};

// ─── Shared keyframe injection ───────────────────────────────────────────────
const ONBOARDING_STYLES = `
  @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;1,300;1,400;1,500&display=swap');
  @keyframes breathe {
    0%, 100% { transform: scale(1);    opacity: 0.72; }
    50%       { transform: scale(1.22); opacity: 1;    }
  }
  @keyframes ob-fadeUp {
    from { opacity: 0; transform: translateY(14px); }
    to   { opacity: 1; transform: translateY(0);    }
  }
`;

// ─── Local primitives (mirrors Agent A contract) ──────────────────────────────

function GlassCard({ children, style, onClick, selected = false }) {
  const [hov, setHov] = useState(false);
  const interactive = Boolean(onClick);
  return (
    <div
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      onKeyDown={interactive ? e => { if (e.key === 'Enter' || e.key === ' ') onClick?.(e); } : undefined}
      style={{
        background:           selected ? `rgba(201,168,76,0.13)` : tokens.glassDark,
        backdropFilter:       tokens.blur.card,
        WebkitBackdropFilter: tokens.blur.card,
        borderRadius:         tokens.radius.card,
        border:               selected
          ? `1px solid ${tokens.gold}`
          : `1px solid ${tokens.glassBorder}`,
        boxShadow: selected
          ? `0 0 0 1px ${tokens.gold}, 0 0 28px ${tokens.glassGlow}, 0 8px 32px rgba(0,0,0,0.38)`
          : `0 0 0 1px ${tokens.glassBorder}, 0 8px 28px rgba(0,0,0,0.32)`,
        padding:   tokens.spacing.lg,
        transition: tokens.transition,
        cursor:    interactive ? 'pointer' : 'default',
        transform: hov && interactive ? 'translateY(-2px) scale(1.005)' : 'none',
        willChange: 'transform',
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function GlassButton({ children, onClick, disabled = false, variant = 'primary', style }) {
  const [hov, setHov] = useState(false);
  const [pressed, setPressed] = useState(false);

  const base = {
    display:              'inline-flex',
    alignItems:           'center',
    justifyContent:       'center',
    gap:                  tokens.spacing.xs,
    padding:              '14px 32px',
    borderRadius:         tokens.radius.pill,
    fontFamily:           tokens.font.ui,
    fontSize:             '15px',
    fontWeight:           '600',
    letterSpacing:        '0.02em',
    cursor:               disabled ? 'not-allowed' : 'pointer',
    opacity:              disabled ? 0.38 : 1,
    transition:           tokens.transition,
    backdropFilter:       tokens.blur.sm,
    WebkitBackdropFilter: tokens.blur.sm,
    userSelect:           'none',
    transform:            pressed ? 'scale(0.96)' : hov && !disabled ? 'scale(1.03)' : 'scale(1)',
    border:               'none',
  };

  const variants = {
    primary: {
      background: hov && !disabled
        ? `linear-gradient(135deg, ${tokens.goldLight}, ${tokens.gold})`
        : `linear-gradient(135deg, ${tokens.gold}, ${tokens.goldDim})`,
      color:     tokens.bgDeep,
      boxShadow: hov && !disabled
        ? `0 0 28px ${tokens.glassGlow}, 0 4px 16px rgba(0,0,0,0.3)`
        : `0 0 14px ${tokens.glassGlow}`,
      border:    `1px solid ${tokens.goldLight}`,
    },
    ghost: {
      background: hov && !disabled ? tokens.glassLight : tokens.glassDark,
      color:      tokens.textPrimary,
      boxShadow:  hov && !disabled ? `0 0 14px ${tokens.glassGlow}` : 'none',
      border:     `1px solid ${tokens.glassBorder}`,
    },
  };

  return (
    <button
      onClick={disabled ? undefined : onClick}
      disabled={disabled}
      onMouseEnter={() => !disabled && setHov(true)}
      onMouseLeave={() => { setHov(false); setPressed(false); }}
      onMouseDown={() => !disabled && setPressed(true)}
      onMouseUp={() => setPressed(false)}
      style={{ ...base, ...variants[variant] ?? variants.primary, ...style }}
    >
      {children}
    </button>
  );
}

function SectionLabel({ children, style: overrideStyle }) {
  return (
    <div style={{
      fontFamily:    tokens.font.ui,
      fontSize:      '10px',
      fontWeight:    '700',
      letterSpacing: '0.12em',
      textTransform: 'uppercase',
      color:         tokens.gold,
      opacity:       0.85,
      userSelect:    'none',
      ...overrideStyle,
    }}>
      {children}
    </div>
  );
}

// ─── Step indicator ───────────────────────────────────────────────────────────

function StepDots({ total, current }) {
  return (
    <div
      role="progressbar"
      aria-valuenow={current + 1}
      aria-valuemin={1}
      aria-valuemax={total}
      aria-label={`Step ${current + 1} of ${total}`}
      style={{ display: 'flex', gap: tokens.spacing.sm, justifyContent: 'center', marginBottom: tokens.spacing.lg }}
    >
      {Array.from({ length: total }).map((_, i) => (
        <div
          key={i}
          style={{
            width:        i === current ? '20px' : '6px',
            height:       '6px',
            borderRadius: tokens.radius.pill,
            background:   i === current ? tokens.gold : i < current ? tokens.goldDim : tokens.textMuted,
            transition:   tokens.transition,
            flexShrink:   0,
            boxShadow:    i === current ? `0 0 8px ${tokens.goldDim}` : 'none',
          }}
        />
      ))}
    </div>
  );
}

// ─── Page wrapper ─────────────────────────────────────────────────────────────

function OnboardingPage({ children, style }) {
  return (
    <div style={{
      minHeight:      '100vh',
      display:        'flex',
      flexDirection:  'column',
      alignItems:     'center',
      justifyContent: 'center',
      background:     `radial-gradient(ellipse 70% 55% at 50% 42%, rgba(201,168,76,0.09) 0%, transparent 72%),
                       linear-gradient(160deg, ${tokens.bgDeep} 0%, #0E0E16 100%)`,
      padding:        tokens.spacing.xl,
      overflowY:      'auto',
      animation:      'ob-fadeUp 0.38s cubic-bezier(0.25,0.46,0.45,0.94)',
      ...style,
    }}>
      {children}
    </div>
  );
}

// ─── Screen 1: Intro ─────────────────────────────────────────────────────────

function IntroScreen({ onNext }) {
  return (
    <OnboardingPage>
      <div style={{ maxWidth: '380px', width: '100%', textAlign: 'center' }}>

        {/* Gold radial emblem */}
        <div
          aria-hidden="true"
          style={{
            width:         '88px',
            height:        '88px',
            borderRadius:  '50%',
            margin:        '0 auto',
            marginBottom:  tokens.spacing.xl,
            background:    `radial-gradient(circle at 36% 36%, ${tokens.goldLight}, ${tokens.goldDim})`,
            boxShadow:     `0 0 64px rgba(201,168,76,0.32), 0 0 0 1px ${tokens.glassBorder}`,
            display:       'flex',
            alignItems:    'center',
            justifyContent:'center',
            animation:     'breathe 3.5s ease-in-out infinite',
          }}
        >
          <Sparkles size={32} color={tokens.bgDeep} strokeWidth={1.5} />
        </div>

        {/* Title */}
        <h1 style={{
          fontFamily:   tokens.font.display,
          fontSize:     '58px',
          fontWeight:   '300',
          fontStyle:    'italic',
          color:        tokens.textPrimary,
          letterSpacing:'0.02em',
          lineHeight:   1.1,
          marginBottom: tokens.spacing.xs,
        }}>
          Berean
        </h1>

        {/* Tagline */}
        <p style={{
          fontFamily:    tokens.font.ui,
          fontSize:      '13px',
          fontWeight:    '500',
          letterSpacing: '0.10em',
          textTransform: 'uppercase',
          color:         tokens.goldLight,
          opacity:       0.82,
          marginBottom:  tokens.spacing.sm,
        }}>
          Stay rooted. Examine daily.
        </p>

        {/* Acts 17:11 reference */}
        <p style={{
          fontFamily:   tokens.font.display,
          fontSize:     '13px',
          fontStyle:    'italic',
          color:        tokens.textMuted,
          marginBottom: tokens.spacing.xl,
          letterSpacing:'0.04em',
        }}>
          Acts 17:11
        </p>

        {/* Body copy */}
        <GlassCard style={{ textAlign: 'left', marginBottom: tokens.spacing.xl }}>
          <p style={{
            fontFamily: tokens.font.ui,
            fontSize:   '15px',
            color:      tokens.textSecondary,
            lineHeight: 1.72,
            marginBottom: tokens.spacing.md,
          }}>
            Each morning, Berean prepares a personal arc of Scripture, prayer,
            and reflection — tied to where you actually are in your walk.
          </p>
          <p style={{
            fontFamily: tokens.font.ui,
            fontSize:   '15px',
            color:      tokens.textSecondary,
            lineHeight: 1.72,
            marginBottom: tokens.spacing.md,
          }}>
            It reads your reading plan, your prayer list, your community — not
            a stranger's feed. Formation toward faithfulness is the only goal.
          </p>
          <p style={{
            fontFamily: tokens.font.display,
            fontSize:   '16px',
            fontStyle:  'italic',
            color:      tokens.textMuted,
            lineHeight: 1.6,
          }}>
            Formation over information. Faithfulness over productivity.
          </p>
        </GlassCard>

        <GlassButton
          variant="primary"
          onClick={onNext}
          style={{ width: '100%', fontSize: '16px', padding: '16px 32px' }}
        >
          Begin <ChevronRight size={18} />
        </GlassButton>
      </div>
    </OnboardingPage>
  );
}

// ─── Screen 2: Topic Picker ───────────────────────────────────────────────────

const TOPIC_OPTIONS = [
  { id: 'verse',     label: 'Daily verse & reflection',  desc: 'One verse tied to your reading plan, with a short invitation to reflect.' },
  { id: 'plan',      label: 'Reading-plan momentum',     desc: 'Know where you are today and keep your pace.' },
  { id: 'prayer',    label: 'Prayer follow-ups',         desc: 'Revisit who you\'ve been praying for and celebrate answered prayer.' },
  { id: 'sanctuary', label: 'Sanctuary stirrings',       desc: 'Open requests and threads from communities you\'ve joined.' },
  { id: 'study',     label: 'Open study thread',         desc: 'A passage you highlighted or a study left unfinished.' },
  { id: 'memory',    label: 'Memory-verse practice',     desc: 'Spaced repetition to help Scripture take root.' },
  { id: 'seasonal',  label: 'Seasonal rhythm',           desc: 'Invitations shaped by the liturgical calendar.' },
];

function TopicPickerScreen({ selectedTopics, onToggle, onNext }) {
  const canContinue = selectedTopics.length >= 2;

  return (
    <OnboardingPage style={{ justifyContent: 'flex-start', paddingTop: tokens.spacing.xl }}>
      <div style={{ maxWidth: '480px', width: '100%' }}>

        <StepDots total={5} current={1} />

        <SectionLabel style={{ marginBottom: tokens.spacing.sm }}>Berean</SectionLabel>
        <h2 style={{
          fontFamily:   tokens.font.display,
          fontSize:     '34px',
          fontWeight:   '300',
          color:        tokens.textPrimary,
          lineHeight:   1.25,
          marginBottom: tokens.spacing.sm,
        }}>
          What would you like Berean to surface each morning?
        </h2>
        <p style={{
          fontFamily:   tokens.font.ui,
          fontSize:     '13px',
          color:        tokens.textMuted,
          marginBottom: tokens.spacing.lg,
        }}>
          Choose at least two. You can change these any time in Settings.
        </p>

        {/* Topic chips grid */}
        <div style={{
          display:      'flex',
          flexWrap:     'wrap',
          gap:          tokens.spacing.sm,
          marginBottom: tokens.spacing.xl,
        }}>
          {TOPIC_OPTIONS.map(topic => {
            const active = selectedTopics.includes(topic.id);
            return (
              <button
                key={topic.id}
                onClick={() => onToggle(topic.id)}
                aria-pressed={active}
                aria-label={topic.label}
                style={{
                  display:              'inline-flex',
                  flexDirection:        'column',
                  alignItems:           'flex-start',
                  gap:                  '4px',
                  padding:              `${tokens.spacing.md} ${tokens.spacing.lg}`,
                  borderRadius:         tokens.radius.lg,
                  background:           active ? `rgba(201,168,76,0.14)` : tokens.glassDark,
                  backdropFilter:       tokens.blur.card,
                  WebkitBackdropFilter: tokens.blur.card,
                  border:               active
                    ? `1px solid ${tokens.gold}`
                    : `1px solid ${tokens.glassBorder}`,
                  boxShadow:            active
                    ? `0 0 0 1px ${tokens.gold}, 0 0 20px ${tokens.glassGlow}`
                    : `0 0 0 1px ${tokens.glassBorder}`,
                  cursor:     'pointer',
                  transition: tokens.transition,
                  minWidth:   '140px',
                  flex:       '1 1 140px',
                  textAlign:  'left',
                }}
              >
                <span style={{
                  fontFamily:  tokens.font.ui,
                  fontSize:    '13px',
                  fontWeight:  '600',
                  color:       active ? tokens.goldLight : tokens.textPrimary,
                  transition:  tokens.transition,
                  display:     'flex',
                  alignItems:  'center',
                  gap:         tokens.spacing.xs,
                }}>
                  {active && <Check size={13} color={tokens.gold} strokeWidth={2.5} />}
                  {topic.label}
                </span>
                <span style={{
                  fontFamily: tokens.font.ui,
                  fontSize:   '11px',
                  color:      tokens.textMuted,
                  lineHeight: 1.5,
                  fontWeight: '400',
                }}>
                  {topic.desc}
                </span>
              </button>
            );
          })}
        </div>

        {/* Selection count hint */}
        <p style={{
          fontFamily:   tokens.font.ui,
          fontSize:     '12px',
          color:        canContinue ? tokens.textMuted : tokens.gold,
          textAlign:    'center',
          marginBottom: tokens.spacing.md,
          transition:   tokens.transition,
        }}>
          {selectedTopics.length === 0
            ? 'Select at least two to continue'
            : selectedTopics.length === 1
            ? 'Select one more to continue'
            : `${selectedTopics.length} selected`}
        </p>

        <GlassButton
          variant="primary"
          disabled={!canContinue}
          onClick={onNext}
          style={{ width: '100%', fontSize: '16px', padding: '16px 32px' }}
        >
          Continue <ChevronRight size={18} />
        </GlassButton>
      </div>
    </OnboardingPage>
  );
}

// ─── Screen 3: Integrations Consent ──────────────────────────────────────────

const INTEGRATION_OPTIONS = [
  {
    id:    'youversion',
    icon:  BookOpen,
    name:  'YouVersion',
    desc:  'Your reading plan progress and highlighted verses',
    reads: 'Reading plan position, bookmarks, and highlights you\'ve made.',
  },
  {
    id:    'sanctuaries',
    icon:  Users,
    name:  'Sanctuaries',
    desc:  'Open prayer requests from your communities',
    reads: 'Open prayer threads and activity in Sanctuaries you\'ve joined.',
  },
  {
    id:    'prayerList',
    icon:  Heart,
    name:  'Prayer List',
    desc:  'Your personal prayer items',
    reads: 'Who you\'re praying for, when you last prayed, and status.',
  },
];

function IntegrationToggleRow({ option, enabled, onToggle }) {
  const Icon = option.icon;
  return (
    <div style={{
      display:        'flex',
      alignItems:     'flex-start',
      gap:            tokens.spacing.md,
      padding:        tokens.spacing.md,
      borderRadius:   tokens.radius.lg,
      background:     enabled ? `rgba(201,168,76,0.07)` : tokens.glassDark,
      border:         `1px solid ${enabled ? tokens.gold : tokens.glassBorder}`,
      backdropFilter: tokens.blur.sm,
      WebkitBackdropFilter: tokens.blur.sm,
      transition:     tokens.transition,
      marginBottom:   tokens.spacing.sm,
    }}>
      {/* Icon */}
      <div style={{
        width:         '38px',
        height:        '38px',
        borderRadius:  tokens.radius.pill,
        background:    enabled ? `rgba(201,168,76,0.18)` : tokens.glassLight,
        border:        `1px solid ${enabled ? tokens.gold : tokens.glassBorder}`,
        display:       'flex',
        alignItems:    'center',
        justifyContent:'center',
        flexShrink:    0,
        transition:    tokens.transition,
      }}>
        <Icon
          size={18}
          color={enabled ? tokens.gold : tokens.textMuted}
          strokeWidth={1.6}
        />
      </div>

      {/* Text */}
      <div style={{ flex: 1 }}>
        <p style={{
          fontFamily:  tokens.font.ui,
          fontSize:    '14px',
          fontWeight:  '600',
          color:       enabled ? tokens.textPrimary : tokens.textSecondary,
          marginBottom:'3px',
          transition:  tokens.transition,
        }}>
          {option.name}
        </p>
        <p style={{
          fontFamily: tokens.font.ui,
          fontSize:   '12px',
          color:      tokens.textMuted,
          lineHeight: 1.55,
        }}>
          {option.desc}
        </p>
        <p style={{
          fontFamily:  tokens.font.ui,
          fontSize:    '11px',
          color:       tokens.textMuted,
          lineHeight:  1.5,
          marginTop:   '4px',
          opacity:     0.72,
        }}>
          Reads: {option.reads}
        </p>
      </div>

      {/* Toggle */}
      <button
        role="switch"
        aria-checked={enabled}
        aria-label={`${enabled ? 'Disable' : 'Enable'} ${option.name}`}
        onClick={() => onToggle(option.id)}
        style={{
          width:         '44px',
          height:        '26px',
          borderRadius:  '13px',
          background:    enabled
            ? `linear-gradient(135deg, ${tokens.gold}, ${tokens.goldDim})`
            : 'rgba(255,255,255,0.10)',
          border:        `1px solid ${enabled ? tokens.gold : tokens.glassBorder}`,
          cursor:        'pointer',
          padding:       '0',
          position:      'relative',
          transition:    tokens.transition,
          flexShrink:    0,
          boxShadow:     enabled ? `0 0 12px ${tokens.glassGlow}` : 'none',
        }}
      >
        <span style={{
          position:   'absolute',
          top:        '3px',
          left:       enabled ? '21px' : '3px',
          width:      '18px',
          height:     '18px',
          borderRadius:'50%',
          background:  enabled ? tokens.bgDeep : tokens.textMuted,
          transition:  tokens.transition,
          display:     'block',
        }} />
      </button>
    </div>
  );
}

function IntegrationsConsentScreen({ integrations, onToggle, onNext }) {
  return (
    <OnboardingPage style={{ justifyContent: 'flex-start', paddingTop: tokens.spacing.xl }}>
      <div style={{ maxWidth: '480px', width: '100%' }}>

        <StepDots total={5} current={2} />

        <SectionLabel style={{ marginBottom: tokens.spacing.sm }}>Data & Privacy</SectionLabel>
        <h2 style={{
          fontFamily:   tokens.font.display,
          fontSize:     '34px',
          fontWeight:   '300',
          color:        tokens.textPrimary,
          lineHeight:   1.25,
          marginBottom: tokens.spacing.sm,
        }}>
          What can Berean learn from?
        </h2>
        <p style={{
          fontFamily:   tokens.font.ui,
          fontSize:     '13px',
          color:        tokens.textMuted,
          lineHeight:   1.65,
          marginBottom: tokens.spacing.lg,
        }}>
          All integrations are off by default. Turn on only what you want Berean
          to read. You can change any of this in Settings at any time.
        </p>

        <div style={{ marginBottom: tokens.spacing.xl }}>
          {INTEGRATION_OPTIONS.map(opt => (
            <IntegrationToggleRow
              key={opt.id}
              option={opt}
              enabled={integrations[opt.id] === true}
              onToggle={onToggle}
            />
          ))}
        </div>

        {/* No-dark-pattern note */}
        <div style={{
          padding:      tokens.spacing.md,
          borderRadius: tokens.radius.lg,
          background:   tokens.glassDark,
          border:       `1px solid ${tokens.glassBorder}`,
          marginBottom: tokens.spacing.xl,
        }}>
          <p style={{
            fontFamily: tokens.font.ui,
            fontSize:   '12px',
            color:      tokens.textMuted,
            lineHeight: 1.65,
          }}>
            Berean works with or without any of these. Turning them off doesn't
            limit what Berean can do — it just personalizes less deeply.
          </p>
        </div>

        <GlassButton
          variant="primary"
          onClick={onNext}
          style={{ width: '100%', fontSize: '16px', padding: '16px 32px' }}
        >
          Continue <ChevronRight size={18} />
        </GlassButton>
      </div>
    </OnboardingPage>
  );
}

// ─── Screen 4: Notification Preference ───────────────────────────────────────

const TIME_OPTIONS = [
  { id: '6am',  label: '6:00 AM' },
  { id: '7am',  label: '7:00 AM' },
  { id: '8am',  label: '8:00 AM' },
  { id: '9am',  label: '9:00 AM' },
  { id: 'custom', label: 'Custom…' },
];

function NotificationScreen({ notificationTime, onSelect, onNext }) {
  return (
    <OnboardingPage style={{ justifyContent: 'flex-start', paddingTop: tokens.spacing.xl }}>
      <div style={{ maxWidth: '480px', width: '100%' }}>

        <StepDots total={5} current={3} />

        <div style={{ textAlign: 'center', marginBottom: tokens.spacing.xl }}>
          <div style={{
            width:         '56px',
            height:        '56px',
            borderRadius:  tokens.radius.pill,
            background:    `rgba(201,168,76,0.12)`,
            border:        `1px solid ${tokens.glassBorder}`,
            display:       'flex',
            alignItems:    'center',
            justifyContent:'center',
            margin:        '0 auto',
            marginBottom:  tokens.spacing.lg,
          }}>
            <Bell size={24} color={tokens.gold} strokeWidth={1.6} />
          </div>

          <SectionLabel style={{ justifyContent: 'center', marginBottom: tokens.spacing.sm }}>
            Morning Delivery
          </SectionLabel>
          <h2 style={{
            fontFamily:   tokens.font.display,
            fontSize:     '34px',
            fontWeight:   '300',
            color:        tokens.textPrimary,
            lineHeight:   1.25,
            marginBottom: tokens.spacing.sm,
          }}>
            When should your Berean arrive?
          </h2>
          <p style={{
            fontFamily: tokens.font.ui,
            fontSize:   '13px',
            color:      tokens.textMuted,
            lineHeight: 1.65,
          }}>
            Berean is prepared overnight so it's ready when you wake.
          </p>
        </div>

        {/* Time chips */}
        <div style={{
          display:        'flex',
          flexWrap:       'wrap',
          gap:            tokens.spacing.sm,
          justifyContent: 'center',
          marginBottom:   tokens.spacing.xl,
        }}>
          {TIME_OPTIONS.map(opt => {
            const active = notificationTime === opt.id;
            return (
              <button
                key={opt.id}
                role="radio"
                aria-checked={active}
                aria-label={opt.label}
                onClick={() => onSelect(opt.id)}
                style={{
                  padding:              `${tokens.spacing.md} ${tokens.spacing.lg}`,
                  borderRadius:         tokens.radius.pill,
                  background:           active ? `rgba(201,168,76,0.18)` : tokens.glassDark,
                  backdropFilter:       tokens.blur.sm,
                  WebkitBackdropFilter: tokens.blur.sm,
                  border:               active
                    ? `1px solid ${tokens.gold}`
                    : `1px solid ${tokens.glassBorder}`,
                  boxShadow:            active ? `0 0 18px ${tokens.glassGlow}` : 'none',
                  color:                active ? tokens.goldLight : tokens.textSecondary,
                  fontFamily:           tokens.font.ui,
                  fontSize:             '15px',
                  fontWeight:           active ? '600' : '400',
                  cursor:               'pointer',
                  transition:           tokens.transition,
                  minWidth:             '96px',
                }}
              >
                {active && (
                  <Check
                    size={13}
                    color={tokens.gold}
                    strokeWidth={2.5}
                    style={{ marginRight: '6px', verticalAlign: 'middle' }}
                  />
                )}
                {opt.label}
              </button>
            );
          })}
        </div>

        {/* Custom time note */}
        {notificationTime === 'custom' && (
          <div style={{
            padding:      tokens.spacing.md,
            borderRadius: tokens.radius.lg,
            background:   tokens.glassDark,
            border:       `1px solid ${tokens.glassBorder}`,
            marginBottom: tokens.spacing.lg,
            textAlign:    'center',
          }}>
            <p style={{
              fontFamily: tokens.font.ui,
              fontSize:   '13px',
              color:      tokens.textSecondary,
              lineHeight: 1.6,
            }}>
              You can set a custom time in Settings after onboarding.
            </p>
          </div>
        )}

        <GlassButton
          variant="primary"
          onClick={onNext}
          style={{ width: '100%', fontSize: '16px', padding: '16px 32px' }}
        >
          Continue <ChevronRight size={18} />
        </GlassButton>

        <p style={{
          fontFamily:  tokens.font.ui,
          fontSize:    '12px',
          color:       tokens.textMuted,
          textAlign:   'center',
          marginTop:   tokens.spacing.md,
          lineHeight:  1.6,
        }}>
          You can change your notification time in Settings any time.
        </p>
      </div>
    </OnboardingPage>
  );
}

// ─── Screen 5: Completion ─────────────────────────────────────────────────────

function CompletionScreen({ onComplete }) {
  return (
    <OnboardingPage>
      <div style={{ maxWidth: '380px', width: '100%', textAlign: 'center' }}>

        <StepDots total={5} current={4} />

        {/* Pulsing gold orb */}
        <div
          aria-hidden="true"
          style={{
            width:         '96px',
            height:        '96px',
            borderRadius:  '50%',
            margin:        '0 auto',
            marginBottom:  tokens.spacing.xl,
            background:    `radial-gradient(circle at 38% 38%, ${tokens.goldLight}, ${tokens.goldDim})`,
            boxShadow:     `0 0 72px rgba(201,168,76,0.38), 0 0 0 1px ${tokens.glassBorder}`,
            animation:     'breathe 2.8s ease-in-out infinite',
            display:       'flex',
            alignItems:    'center',
            justifyContent:'center',
          }}
        >
          <Sparkles size={36} color={tokens.bgDeep} strokeWidth={1.5} />
        </div>

        <h1 style={{
          fontFamily:   tokens.font.display,
          fontSize:     '38px',
          fontWeight:   '300',
          color:        tokens.textPrimary,
          lineHeight:   1.25,
          marginBottom: tokens.spacing.md,
        }}>
          Your first Berean is being prepared.
        </h1>

        <p style={{
          fontFamily:   tokens.font.display,
          fontSize:     '20px',
          fontStyle:    'italic',
          color:        tokens.goldLight,
          opacity:      0.88,
          lineHeight:   1.55,
          marginBottom: tokens.spacing.xl,
        }}>
          It will be ready in the morning.
        </p>

        <GlassCard style={{ marginBottom: tokens.spacing.xl, textAlign: 'left' }}>
          <p style={{
            fontFamily: tokens.font.ui,
            fontSize:   '14px',
            color:      tokens.textSecondary,
            lineHeight: 1.7,
          }}>
            Overnight, Berean reads where you are in your walk and weaves a personal
            arc of Scripture, prayer, and reflection. Formation over information.
            Faithfulness over productivity.
          </p>
        </GlassCard>

        <p style={{
          fontFamily:   tokens.font.ui,
          fontSize:     '12px',
          color:        tokens.textMuted,
          marginBottom: tokens.spacing.xl,
          lineHeight:   1.65,
        }}>
          You can adjust all of this in Settings any time.
        </p>

        <GlassButton
          variant="primary"
          onClick={onComplete}
          style={{ width: '100%', fontSize: '16px', padding: '16px 32px' }}
        >
          Open Berean <ChevronRight size={18} />
        </GlassButton>
      </div>
    </OnboardingPage>
  );
}

// ─── Root: BereanOnboarding ───────────────────────────────────────────────────

const BereanOnboarding = ({ onComplete }) => {
  // step: 1 = intro, 2 = topics, 3 = integrations, 4 = notifications, 5 = done
  const [step, setStep] = useState(1);

  // Screen 2 state — two preselected to reduce friction
  const [selectedTopics, setSelectedTopics] = useState(['verse', 'prayer']);
  const toggleTopic = (id) =>
    setSelectedTopics(prev =>
      prev.includes(id) ? prev.filter(t => t !== id) : [...prev, id]
    );

  // Screen 3 state — ALL default OFF (spec 5.4)
  const [integrations, setIntegrations] = useState({
    youversion:   false,
    sanctuaries:  false,
    prayerList:   false,
  });
  const toggleIntegration = (id) =>
    setIntegrations(prev => ({ ...prev, [id]: !prev[id] }));

  // Screen 4 state
  const [notificationTime, setNotificationTime] = useState('7am');

  const handleComplete = () => {
    // Bubble preferences to parent; no storage side-effects
    onComplete({ selectedTopics, integrations, notificationTime });
  };

  return (
    <>
      <style>{ONBOARDING_STYLES}</style>

      {step === 1 && (
        <IntroScreen onNext={() => setStep(2)} />
      )}

      {step === 2 && (
        <TopicPickerScreen
          selectedTopics={selectedTopics}
          onToggle={toggleTopic}
          onNext={() => setStep(3)}
        />
      )}

      {step === 3 && (
        <IntegrationsConsentScreen
          integrations={integrations}
          onToggle={toggleIntegration}
          onNext={() => setStep(4)}
        />
      )}

      {step === 4 && (
        <NotificationScreen
          notificationTime={notificationTime}
          onSelect={setNotificationTime}
          onNext={() => setStep(5)}
        />
      )}

      {step === 5 && (
        <CompletionScreen onComplete={handleComplete} />
      )}
    </>
  );
};
