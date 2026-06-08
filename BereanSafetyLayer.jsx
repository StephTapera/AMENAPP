// === AGENT E: SAFETY LAYER ===
// BereanSafetyLayer.jsx — Hard-dependency safety module for the Berean daily formation companion
//
// EXPORTS (6 named consts — no default export):
//   CrisisCard            — renders crisis-sensitivity prayer items; no AI, no platitudes
//   TenderCard            — renders tender-sensitivity prayer items; warm, community-oriented
//   DoctrinalHumilityNote — small italic footer appended to any AI-generated reflection
//   ConsentRow            — reusable row UI for a single integration consent (default OFF)
//   SafetyGate            — { isSafeToReflect, renderSafeCard } utility object
//   WhySeeingThisSheet    — modal explaining why a specific card appeared
//
// HARD GUARDRAILS (this module wins every conflict):
//   G1. No invented Scripture. getVerse() is the only source. MockBadge on every verse.
//   G2. Crisis items → CrisisCard. Never AI reflection. Never Scripture-as-answer.
//   G3. Tender items → TenderCard. Warm, human, no AI wisdom, no platitudes.
//   G4. All integrations default OFF. ConsentRow.enabled defaults to false.
//   G5. Reflections are invitations. DoctrinalHumilityNote appended to every AI reflection.
//   G6. Every crisis/tender card ends toward real people, not more app engagement.
//
// Assumes in scope (no import statements):
//   React, useState, useEffect        — from React
//   Heart, Phone, MessageSquare,
//   Users, AlertCircle, Info,
//   X, Shield, CheckCircle            — from lucide-react
//   GlassCard, GlassButton,
//   SectionLabel, MockBadge           — Agent A primitives
//   tokens (aliased as T below)       — Agent A design tokens
//
// Token fallback: this file defines a local T alias so the module is self-contained
// if Agent A's tokens are not yet in scope. Agent F should ensure Agent A runs first.

// ─── Local token alias (mirrors Agent A TOKENS exactly) ────────────────────────
// If Agent A has already defined `tokens` or `T`, this const is shadowed by the
// outer scope in Agent F's assembly. Defined here for standalone module safety.
const T = (typeof tokens !== 'undefined') ? tokens : {
  gold:            '#C9A84C',
  goldLight:       '#E8CB7A',
  goldDim:         '#8A6F2E',
  glassLight:      'rgba(255,255,255,0.07)',
  glassDark:       'rgba(255,255,255,0.04)',
  glassBorder:     'rgba(201,168,76,0.18)',
  glassGlow:       'rgba(201,168,76,0.10)',
  bgDeep:          '#0A0A0F',
  textPrimary:     '#F5F0E8',
  textSecondary:   '#B8AFA0',
  textMuted:       '#6B6460',
  crisisRed:       '#D93025',
  crisisRedSoft:   'rgba(217,48,37,0.15)',
  tenderBlue:      '#4A9ECC',
  tenderBlueSoft:  'rgba(74,158,204,0.12)',
  successGreen:    '#3DAA6E',
  spacing:  { xs: '4px', sm: '8px', md: '16px', lg: '24px', xl: '40px' },
  radius:   { card: '20px', pill: '9999px', xl: '28px' },
  blur:     { card: 'blur(16px)', sm: 'blur(8px)' },
  font: {
    display: "'Cormorant Garamond', Georgia, serif",
    ui:      "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif",
  },
  transition: 'all 0.35s cubic-bezier(0.25, 0.46, 0.45, 0.94)',
};

// Resolve Agent A primitives with local fallbacks —————————————————————————————
// Agent F can override these by defining GlassCard etc. before this module loads.

function _LocalGlassCard({ children, style, danger = false, tender = false, elevated = false, glow = false }) {
  const borderColor = danger   ? T.crisisRed
                    : tender   ? T.tenderBlue
                    :            T.glassBorder;
  const fillColor   = danger   ? T.crisisRedSoft
                    : tender   ? T.tenderBlueSoft
                    : elevated ? 'rgba(255,255,255,0.07)'
                    :            T.glassDark;
  const glowShadow  = danger   ? `0 0 32px ${T.crisisRedSoft}`
                    : tender   ? `0 0 32px ${T.tenderBlueSoft}`
                    : glow     ? `0 0 40px ${T.glassGlow}`
                    :            null;
  const boxShadow = [
    `0 0 0 1px ${borderColor}`,
    elevated
      ? '0 20px 60px rgba(0,0,0,0.55), 0 4px 16px rgba(0,0,0,0.35)'
      : '0 8px 32px rgba(0,0,0,0.40), 0 2px 8px rgba(0,0,0,0.25)',
    glowShadow,
  ].filter(Boolean).join(', ');

  return (
    <div style={{
      position:             'relative',
      background:           fillColor,
      backdropFilter:       T.blur.card,
      WebkitBackdropFilter: T.blur.card,
      borderRadius:         T.radius.card,
      boxShadow,
      padding:              T.spacing.lg,
      transition:           T.transition,
      ...style,
    }}>
      {children}
    </div>
  );
}

function _LocalGlassButton({ children, onClick, variant = 'primary', size = 'md', disabled = false, style }) {
  const [hov, setHov] = useState(false);
  const sizeMap = {
    sm: { padding: '6px 14px',  fontSize: '12px' },
    md: { padding: '9px 22px',  fontSize: '14px' },
    lg: { padding: '13px 32px', fontSize: '16px' },
  };
  const dim = sizeMap[size] ?? sizeMap.md;
  const variantMap = {
    primary: {
      background: hov
        ? `linear-gradient(135deg, ${T.goldLight}, ${T.gold})`
        : `linear-gradient(135deg, ${T.gold}, ${T.goldDim})`,
      color:     T.bgDeep,
      border:    `1px solid ${T.goldLight}`,
      fontWeight:'600',
    },
    ghost: {
      background: hov ? T.glassLight : T.glassDark,
      color:      T.textPrimary,
      border:     `1px solid ${T.glassBorder}`,
      fontWeight: '500',
    },
    danger: {
      background: hov ? T.crisisRed : T.crisisRedSoft,
      color:      hov ? '#fff' : T.crisisRed,
      border:     `1px solid ${T.crisisRed}`,
      fontWeight: '600',
    },
    teal: {
      background: hov ? 'rgba(74,158,204,0.25)' : 'rgba(74,158,204,0.12)',
      color:      T.tenderBlue,
      border:     `1px solid rgba(74,158,204,0.35)`,
      fontWeight: '500',
    },
  };
  const v = variantMap[variant] ?? variantMap.primary;

  return (
    <button
      onClick={disabled ? undefined : onClick}
      disabled={disabled}
      onMouseEnter={() => !disabled && setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:             'inline-flex',
        alignItems:          'center',
        justifyContent:      'center',
        gap:                 T.spacing.xs,
        borderRadius:        T.radius.pill,
        backdropFilter:      T.blur.sm,
        WebkitBackdropFilter:T.blur.sm,
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

function _LocalSectionLabel({ children, icon, style: overrideStyle }) {
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
      color:         T.gold,
      opacity:       0.85,
      userSelect:    'none',
      ...overrideStyle,
    }}>
      {icon && (
        <span aria-hidden="true" style={{ fontSize: '12px', lineHeight: 1, flexShrink: 0 }}>
          {icon}
        </span>
      )}
      <span>{children}</span>
    </div>
  );
}

function _LocalMockBadge() {
  return (
    <span style={{
      display:      'inline-block',
      fontFamily:   T.font.ui,
      fontSize:     '9px',
      color:        T.textMuted,
      background:   'rgba(255,255,255,0.04)',
      border:       '1px solid rgba(255,255,255,0.08)',
      borderRadius: '6px',
      padding:      '2px 7px',
      lineHeight:   1.4,
    }}>
      Prototype — mock text. Real Scripture from YouVersion license only.
    </span>
  );
}

// Agent A resolution: prefer injected primitives, fall back to locals
const _Card    = typeof GlassCard    !== 'undefined' ? GlassCard    : _LocalGlassCard;
const _Btn     = typeof GlassButton  !== 'undefined' ? GlassButton  : _LocalGlassButton;
const _Label   = typeof SectionLabel !== 'undefined' ? SectionLabel : _LocalSectionLabel;
const _Badge   = typeof MockBadge    !== 'undefined' ? MockBadge    : _LocalMockBadge;

// ─── Helper: resource link row ────────────────────────────────────────────────
// Used exclusively inside CrisisCard. A plain anchor styled as a tappable row.
function _CrisisResourceRow({ title, subtitle, href, icon: Icon }) {
  const [hov, setHov] = useState(false);
  return (
    <a
      href={href}
      aria-label={title}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:        'flex',
        alignItems:     'center',
        gap:            T.spacing.md,
        padding:        '12px 14px',
        background:     hov ? 'rgba(217,48,37,0.14)' : 'rgba(217,48,37,0.07)',
        borderRadius:   T.radius.card,
        border:         `1px solid ${hov ? 'rgba(217,48,37,0.40)' : 'rgba(217,48,37,0.20)'}`,
        textDecoration: 'none',
        transition:     T.transition,
      }}
    >
      {Icon && (
        <span style={{
          width:          '36px',
          height:         '36px',
          borderRadius:   T.radius.pill,
          background:     'rgba(217,48,37,0.12)',
          border:         '1px solid rgba(217,48,37,0.25)',
          display:        'flex',
          alignItems:     'center',
          justifyContent: 'center',
          flexShrink:     0,
        }}>
          <Icon size={16} color={T.crisisRed} strokeWidth={1.8} aria-hidden="true" />
        </span>
      )}
      <div style={{ flex: 1 }}>
        <p style={{ fontFamily: T.font.ui, fontSize: '13px', fontWeight: '600', color: T.textPrimary, marginBottom: '2px' }}>
          {title}
        </p>
        <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.textMuted }}>
          {subtitle}
        </p>
      </div>
    </a>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT 1: CrisisCard
// ─────────────────────────────────────────────────────────────────────────────
// Props: { prayerItem }
//   prayerItem.sensitivity must === 'crisis'
//
// GUARDRAILS enforced:
//   - No AI reflection (not even a quote framed as guidance)
//   - No Scripture "assigned" to the crisis as an answer
//   - No platitudes ("It'll be okay", "God has a plan")
//   - Real crisis hotlines with real numbers (G2)
//   - Footer explicitly states Berean is NOT a substitute for human presence (G6)
//   - No "Why am I seeing this?" button — crisis items are not surfaced by the algorithm

const CrisisCard = ({ prayerItem }) => {
  const subject = prayerItem?.subject ?? 'something heavy';
  const forWhom = prayerItem?.forWhom ?? null;

  return (
    <_Card danger>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: T.spacing.sm, marginBottom: T.spacing.md }}>
        <div style={{
          width:          '40px',
          height:         '40px',
          borderRadius:   T.radius.pill,
          background:     'rgba(217,48,37,0.12)',
          border:         `1px solid rgba(217,48,37,0.28)`,
          display:        'flex',
          alignItems:     'center',
          justifyContent: 'center',
          flexShrink:     0,
        }}>
          <Shield size={18} color={T.crisisRed} strokeWidth={1.8} aria-hidden="true" />
        </div>
        <_Label style={{ color: T.crisisRed, opacity: 1 }}>
          Holding Space
        </_Label>
      </div>

      {/* Warm opening — human voice, not AI */}
      <p style={{
        fontFamily:   T.font.display,
        fontSize:     '22px',
        fontStyle:    'italic',
        color:        T.textPrimary,
        lineHeight:   1.55,
        marginBottom: T.spacing.md,
      }}>
        You've been carrying something heavy
        {forWhom && forWhom !== 'Myself' && forWhom !== 'Self'
          ? ` for ${forWhom}`
          : ''
        }.
      </p>

      {/* Human presence nudge — explicitly NOT AI advice */}
      <p style={{
        fontFamily:   T.font.ui,
        fontSize:     '14px',
        color:        T.textSecondary,
        lineHeight:   1.72,
        marginBottom: T.spacing.lg,
      }}>
        This is a moment for real connection — someone who knows you, a pastor, a trusted
        friend, a counselor. There are people trained to walk through this with you right now.
      </p>

      {/* Crisis resources */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: T.spacing.sm, marginBottom: T.spacing.lg }}>
        <p style={{
          fontFamily:   T.font.ui,
          fontSize:     '11px',
          fontWeight:   '700',
          letterSpacing:'0.10em',
          textTransform:'uppercase',
          color:        T.crisisRed,
          opacity:      0.85,
          marginBottom: T.spacing.xs,
        }}>
          Real support, available now
        </p>

        {/* 988 Suicide & Crisis Lifeline */}
        <_CrisisResourceRow
          title="988 Suicide &amp; Crisis Lifeline"
          subtitle="Call or text 988 — free, confidential, 24/7"
          href="tel:988"
          icon={Phone}
        />

        {/* Crisis Text Line */}
        <_CrisisResourceRow
          title="Crisis Text Line"
          subtitle="Text HOME to 741741 — free, 24/7 in the US"
          href="sms:741741?body=HOME"
          icon={MessageSquare}
        />

        {/* Sanctuary CTA — toward community, not app engagement */}
        <div style={{
          display:      'flex',
          alignItems:   'center',
          gap:          T.spacing.md,
          padding:      '12px 14px',
          background:   'rgba(201,168,76,0.06)',
          borderRadius: T.radius.card,
          border:       `1px solid rgba(201,168,76,0.16)`,
        }}>
          <span style={{
            width:          '36px',
            height:         '36px',
            borderRadius:   T.radius.pill,
            background:     'rgba(201,168,76,0.10)',
            border:         `1px solid rgba(201,168,76,0.22)`,
            display:        'flex',
            alignItems:     'center',
            justifyContent: 'center',
            flexShrink:     0,
          }}>
            <Users size={16} color={T.gold} strokeWidth={1.8} aria-hidden="true" />
          </span>
          <div style={{ flex: 1 }}>
            <p style={{ fontFamily: T.font.ui, fontSize: '13px', fontWeight: '600', color: T.textPrimary, marginBottom: '2px' }}>
              Your Sanctuary community is here
            </p>
            <p style={{ fontFamily: T.font.ui, fontSize: '11px', color: T.textMuted, lineHeight: 1.5 }}>
              Reach out to someone in your community who can sit with you.
            </p>
          </div>
        </div>
      </div>

      {/* Footer: explicit disclaimer + no-AI / no-substitute statement */}
      <div style={{
        padding:      `${T.spacing.md} ${T.spacing.md}`,
        background:   'rgba(0,0,0,0.20)',
        borderRadius: T.radius.card,
        border:       `1px solid rgba(217,48,37,0.12)`,
        marginTop:    T.spacing.xs,
      }}>
        <p style={{
          fontFamily:  T.font.ui,
          fontSize:    '12px',
          color:       T.textMuted,
          lineHeight:  1.65,
          textAlign:   'center',
        }}>
          <strong style={{ color: T.textSecondary, fontWeight: '600' }}>You are not alone.</strong>{' '}
          Berean is not a substitute for human presence, professional care, or pastoral support.
          Please reach out to a real person.
        </p>
      </div>

      {/* SAFETY NOTE (dev-visible, not user-visible): this card intentionally
          contains NO AI-generated reflection, NO Scripture "assigned" to the crisis,
          and NO platitudes. Those omissions are deliberate. Do not add them. */}
    </_Card>
  );
};

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT 2: TenderCard
// ─────────────────────────────────────────────────────────────────────────────
// Props: { prayerItem }
//   prayerItem.sensitivity must === 'tender'
//
// GUARDRAILS enforced:
//   - No platitudes ("God has a plan", "It'll be okay")
//   - No AI-generated reflection
//   - No Scripture automatically assigned
//   - Nudge is toward community or pastoral care, never toward app (G6)
//   - Actions are human ("Pray again", "Share with Sanctuary") not algorithmic

const TenderCard = ({ prayerItem }) => {
  const [action, setAction] = useState(null);

  const subject = prayerItem?.subject ?? 'this prayer';
  const forWhom = prayerItem?.forWhom;
  const prayedOn = prayerItem?.prayedOn;

  const daysSince = prayedOn
    ? Math.floor((Date.now() - new Date(prayedOn).getTime()) / 86400000)
    : null;

  return (
    <_Card tender>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: T.spacing.sm, marginBottom: T.spacing.md }}>
        <div style={{
          width:          '40px',
          height:         '40px',
          borderRadius:   T.radius.pill,
          background:     'rgba(74,158,204,0.12)',
          border:         `1px solid rgba(74,158,204,0.28)`,
          display:        'flex',
          alignItems:     'center',
          justifyContent: 'center',
          flexShrink:     0,
        }}>
          <Heart size={18} color={T.tenderBlue} strokeWidth={1.8} aria-hidden="true" />
        </div>
        <_Label style={{ color: T.tenderBlue, opacity: 1 }}>
          Carried in Prayer
        </_Label>
      </div>

      {/* Present-tense, warm framing */}
      <p style={{
        fontFamily:   T.font.display,
        fontSize:     '22px',
        fontStyle:    'italic',
        color:        T.textPrimary,
        lineHeight:   1.5,
        marginBottom: T.spacing.xs,
      }}>
        You've been praying for {forWhom ? <strong style={{ fontStyle: 'normal' }}>{forWhom}</strong> : 'someone you love'}.
      </p>

      {/* Subject + recency */}
      <p style={{
        fontFamily:   T.font.ui,
        fontSize:     '13px',
        color:        T.textSecondary,
        marginBottom: T.spacing.md,
      }}>
        {subject}
        {daysSince !== null && (
          <span style={{ color: T.textMuted, marginLeft: '6px' }}>
            · {daysSince === 0 ? 'today' : `${daysSince} day${daysSince === 1 ? '' : 's'} ago`}
          </span>
        )}
      </p>

      {/* Gentle community nudge — NO platitudes, NO AI wisdom */}
      <div style={{
        padding:      T.spacing.md,
        background:   'rgba(74,158,204,0.08)',
        borderRadius: T.radius.card,
        border:       `1px solid rgba(74,158,204,0.18)`,
        marginBottom: T.spacing.lg,
      }}>
        <p style={{
          fontFamily: T.font.ui,
          fontSize:   '13px',
          color:      T.tenderBlue,
          lineHeight: 1.7,
        }}>
          Sometimes these burdens are lighter with community. If you feel led, consider
          sharing this with your pastor or a trusted friend who can carry it with you.
        </p>
      </div>

      {/* Action options */}
      {!action ? (
        <div style={{ display: 'flex', gap: T.spacing.sm, flexWrap: 'wrap' }}>
          <_Btn
            variant="teal"
            size="sm"
            onClick={() => setAction('prayed')}
            style={{ display: 'flex', alignItems: 'center', gap: '5px' }}
          >
            <Heart size={11} aria-hidden="true" />
            Pray again now
          </_Btn>
          <_Btn
            variant="ghost"
            size="sm"
            onClick={() => setAction('shared')}
            style={{ display: 'flex', alignItems: 'center', gap: '5px' }}
          >
            <Users size={11} aria-hidden="true" />
            Share with Sanctuary
          </_Btn>
        </div>
      ) : (
        <div style={{
          padding:      T.spacing.md,
          background:   'rgba(61,170,110,0.10)',
          border:       `1px solid rgba(61,170,110,0.25)`,
          borderRadius: T.radius.card,
          display:      'flex',
          alignItems:   'center',
          gap:          T.spacing.sm,
        }}>
          <CheckCircle size={14} color={T.successGreen} aria-hidden="true" />
          <p style={{ fontFamily: T.font.ui, fontSize: '13px', color: T.successGreen }}>
            {action === 'prayed' && 'Marked as prayed. Holding this gently with you.'}
            {action === 'shared' && 'Your Sanctuary can carry this with you.'}
          </p>
        </div>
      )}

      {/* Toward-people footer (G6) */}
      <p style={{
        fontFamily:  T.font.ui,
        fontSize:    '11px',
        color:       T.textMuted,
        lineHeight:  1.6,
        marginTop:   T.spacing.md,
        textAlign:   'center',
        fontStyle:   'italic',
      }}>
        Berean holds tender requests gently. It does not generate reflections for them.
      </p>
    </_Card>
  );
};

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT 3: DoctrinalHumilityNote
// ─────────────────────────────────────────────────────────────────────────────
// Appended to the bottom of any AI-generated reflection block.
// Small, muted, italic — present but not intrusive.
// NEVER omit this from AI reflections. Period.

const DoctrinalHumilityNote = ({ style: overrideStyle }) => (
  <p style={{
    fontFamily:  T.font.display,
    fontSize:    '12px',
    fontStyle:   'italic',
    color:       T.textMuted,
    lineHeight:  1.65,
    marginTop:   T.spacing.md,
    paddingTop:  T.spacing.sm,
    borderTop:   `1px solid rgba(255,255,255,0.06)`,
    ...overrideStyle,
  }}>
    This reflection is an invitation, not a ruling. Examine it against Scripture and bring
    it to your community.
  </p>
);

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT 4: ConsentRow
// ─────────────────────────────────────────────────────────────────────────────
// Props: { icon, label, description, enabled, onToggle }
//
// GUARDRAIL (G4): `enabled` MUST default to false at every call site.
//   This component does NOT flip the default internally — it enforces it visually.
//   The parent (onboarding, settings) is responsible for initialising enabled=false.
//
// Reusable context: onboarding Integrations screen, Settings → Berean, any future
//   surface that needs a single-integration consent toggle.

const ConsentRow = ({ icon: Icon, label, description, enabled = false, onToggle }) => {
  const [hov, setHov] = useState(false);

  return (
    <div
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:        'flex',
        alignItems:     'flex-start',
        gap:            T.spacing.md,
        padding:        T.spacing.md,
        borderRadius:   T.radius.card,
        background:     enabled
          ? 'rgba(201,168,76,0.07)'
          : hov ? 'rgba(255,255,255,0.03)' : T.glassDark,
        border:         `1px solid ${enabled ? T.gold : T.glassBorder}`,
        backdropFilter: T.blur.sm,
        WebkitBackdropFilter: T.blur.sm,
        transition:     T.transition,
      }}
    >
      {/* Icon badge */}
      {Icon && (
        <div style={{
          width:          '40px',
          height:         '40px',
          borderRadius:   T.radius.pill,
          background:     enabled
            ? 'rgba(201,168,76,0.18)'
            : 'rgba(255,255,255,0.05)',
          border:         `1px solid ${enabled ? T.gold : T.glassBorder}`,
          display:        'flex',
          alignItems:     'center',
          justifyContent: 'center',
          flexShrink:     0,
          transition:     T.transition,
        }}>
          <Icon
            size={18}
            color={enabled ? T.gold : T.textMuted}
            strokeWidth={1.6}
            aria-hidden="true"
          />
        </div>
      )}

      {/* Text block */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{
          fontFamily:  T.font.ui,
          fontSize:    '14px',
          fontWeight:  '600',
          color:       enabled ? T.textPrimary : T.textSecondary,
          marginBottom:'3px',
          transition:  T.transition,
        }}>
          {label}
        </p>
        <p style={{
          fontFamily: T.font.ui,
          fontSize:   '12px',
          color:      T.textMuted,
          lineHeight: 1.55,
          marginBottom:'4px',
        }}>
          {description}
        </p>
        {/* "Reads:" disclosure — always visible so users know exactly what's accessed */}
        <p style={{
          fontFamily:  T.font.ui,
          fontSize:    '11px',
          color:       T.textMuted,
          lineHeight:  1.5,
          opacity:     0.72,
          fontStyle:   'italic',
        }}>
          {/* Caller passes reads: info inside description, or as a separate `reads` prop.
              Pattern: "Reads: …" is expected at the end of the description string,
              or callers may use a separate line via children. */}
          Default: off. You choose what Berean sees.
        </p>
      </div>

      {/* Toggle switch */}
      <button
        role="switch"
        aria-checked={enabled}
        aria-label={`${enabled ? 'Disable' : 'Enable'} ${label}`}
        onClick={() => onToggle?.()}
        style={{
          width:        '44px',
          height:       '26px',
          borderRadius: '13px',
          background:   enabled
            ? `linear-gradient(135deg, ${T.gold}, ${T.goldDim})`
            : 'rgba(255,255,255,0.10)',
          border:       `1px solid ${enabled ? T.gold : T.glassBorder}`,
          cursor:       'pointer',
          padding:      0,
          position:     'relative',
          transition:   T.transition,
          flexShrink:   0,
          boxShadow:    enabled ? `0 0 12px ${T.glassGlow}` : 'none',
        }}
      >
        <span style={{
          position:     'absolute',
          top:          '3px',
          left:         enabled ? '21px' : '3px',
          width:        '18px',
          height:       '18px',
          borderRadius: '50%',
          background:   enabled ? T.bgDeep : T.textMuted,
          transition:   T.transition,
          display:      'block',
          boxShadow:    '0 1px 4px rgba(0,0,0,0.35)',
        }} />
      </button>
    </div>
  );
};

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT 5: SafetyGate
// ─────────────────────────────────────────────────────────────────────────────
// Not a component — a plain object with two utilities:
//
//   isSafeToReflect(prayerItem)  → boolean
//     Returns true ONLY if sensitivity === 'normal'.
//     false for 'crisis', 'tender', or any unrecognised sensitivity.
//     Agents B, C, D must check this before generating any AI reflection.
//
//   renderSafeCard(prayerItem)  → React element | null
//     Crisis  → <CrisisCard>
//     Tender  → <TenderCard>
//     Normal  → null  (no SafetyGate card needed; normal path is fine)
//
//   isBlockedFromArc(prayerItem) → boolean
//     Returns true for crisis items — these must NEVER enter the ArcCardStack.
//     Tender items MAY enter the arc but must render via TenderCard, not AI reflection.

const SafetyGate = {
  /**
   * Returns true only when it is safe to generate an AI reflection for this item.
   * 'tender' items: safe to surface, NOT safe to reflect on.
   * 'crisis' items: never surface in arc, never reflect, route to CrisisCard only.
   */
  isSafeToReflect(prayerItem) {
    return prayerItem?.sensitivity === 'normal';
  },

  /**
   * Returns the appropriate safety-layer card for non-normal items.
   * Returns null for normal items — they don't need a safety gate.
   * Agent C's CardRenderer calls this before rendering PrayerFollowUpCard.
   */
  renderSafeCard(prayerItem) {
    if (!prayerItem) return null;
    if (prayerItem.sensitivity === 'crisis') {
      return <CrisisCard prayerItem={prayerItem} />;
    }
    if (prayerItem.sensitivity === 'tender') {
      return <TenderCard prayerItem={prayerItem} />;
    }
    return null; // normal items do not need a SafetyGate card
  },

  /**
   * Returns true for crisis items that must be blocked from the ArcCardStack entirely.
   * Tender items are NOT blocked from the arc — they appear in the arc but through TenderCard.
   */
  isBlockedFromArc(prayerItem) {
    return prayerItem?.sensitivity === 'crisis';
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT 6: WhySeeingThisSheet
// ─────────────────────────────────────────────────────────────────────────────
// Props: { card, explanation, onClose }
//   card         — the full CardSpec from Agent D's assembleDailyCards()
//   explanation  — human-readable string (whySeeingThis(card) from Agent D)
//   onClose      — () => void
//
// This sheet explains why Berean surfaced a specific card.
// It MUST accurately represent algorithm transparency — no engagement metrics.
// The small-print paragraph is non-negotiable and must not be removed.

const WhySeeingThisSheet = ({ card, explanation, onClose }) => {
  // Close on Escape key
  useEffect(() => {
    const handler = (e) => { if (e.key === 'Escape') onClose?.(); };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  const cardLabel = card?.type ?? card?.cardType ?? 'This card';

  return (
    /* Dark backdrop — click outside to close */
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Why am I seeing this?"
      onClick={onClose}
      style={{
        position:             'fixed',
        inset:                0,
        zIndex:               1000,
        background:           'rgba(0,0,0,0.72)',
        backdropFilter:       'blur(8px)',
        WebkitBackdropFilter: 'blur(8px)',
        display:              'flex',
        alignItems:           'center',
        justifyContent:       'center',
        padding:              T.spacing.lg,
        animation:            'wsEFadeIn 0.22s ease',
      }}
    >
      {/* Sheet keyframe */}
      <style>{`
        @keyframes wsEFadeIn {
          from { opacity: 0; transform: scale(0.97) translateY(8px); }
          to   { opacity: 1; transform: scale(1)    translateY(0);   }
        }
      `}</style>

      {/* Sheet body — click to stop propagation so backdrop-click only closes if clicking outside */}
      <_Card
        elevated
        style={{
          maxWidth:  '440px',
          width:     '100%',
          animation: 'wsEFadeIn 0.28s cubic-bezier(0.25, 0.46, 0.45, 0.94)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header row */}
        <div style={{
          display:        'flex',
          alignItems:     'flex-start',
          justifyContent: 'space-between',
          marginBottom:   T.spacing.md,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: T.spacing.sm }}>
            <span style={{
              width:          '32px',
              height:         '32px',
              borderRadius:   T.radius.pill,
              background:     'rgba(201,168,76,0.12)',
              border:         `1px solid rgba(201,168,76,0.22)`,
              display:        'flex',
              alignItems:     'center',
              justifyContent: 'center',
              flexShrink:     0,
            }}>
              <Info size={14} color={T.gold} strokeWidth={1.8} aria-hidden="true" />
            </span>
            <_Label>Why am I seeing this?</_Label>
          </div>

          {/* Close button */}
          <button
            aria-label="Close"
            onClick={onClose}
            style={{
              background:   'none',
              border:       'none',
              cursor:       'pointer',
              color:        T.textMuted,
              padding:      '4px',
              borderRadius: T.radius.pill,
              display:      'flex',
              alignItems:   'center',
              justifyContent:'center',
              transition:   T.transition,
              flexShrink:   0,
            }}
          >
            <X size={18} strokeWidth={1.8} aria-hidden="true" />
          </button>
        </div>

        {/* Card type label */}
        <p style={{
          fontFamily:   T.font.display,
          fontSize:     '24px',
          fontWeight:   300,
          color:        T.textPrimary,
          lineHeight:   1.3,
          marginBottom: T.spacing.md,
        }}>
          {cardLabel}
        </p>

        {/* Explanation */}
        <p style={{
          fontFamily:   T.font.ui,
          fontSize:     '14px',
          color:        T.textSecondary,
          lineHeight:   1.7,
          marginBottom: T.spacing.lg,
        }}>
          {explanation ?? 'You selected this type of content in your Berean preferences.'}
        </p>

        {/* Non-negotiable transparency small-print */}
        <div style={{
          padding:      T.spacing.md,
          background:   'rgba(255,255,255,0.03)',
          borderRadius: T.radius.card,
          border:       `1px solid rgba(255,255,255,0.06)`,
          marginBottom: T.spacing.lg,
        }}>
          <p style={{
            fontFamily: T.font.ui,
            fontSize:   '11px',
            color:      T.textMuted,
            lineHeight: 1.65,
          }}>
            Berean selects cards based on your reading plan, prayer history, and Sanctuary
            activity. It never uses engagement scores, time-in-app metrics, or advertising
            signals to decide what you see.
          </p>
        </div>

        {/* Close CTA */}
        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <_Btn variant="ghost" onClick={onClose}>
            Close
          </_Btn>
        </div>
      </_Card>
    </div>
  );
};

// === END AGENT E: SAFETY LAYER ===
//
// Integration checklist for Agent F:
// ─────────────────────────────────────────────────────────────────────────────
// [F1] CrisisCard
//      - BereanFeed (Agent C) renders CrisisCard in place of CrisisPlaceholderCard
//        for every item where prayerItem.sensitivity === 'crisis'
//      - Crisis items are filtered OUT of the ArcCardStack in Agent C (already done)
//      - Crisis items are rendered BELOW the arc section, always
//
// [F2] TenderCard
//      - BereanFeed (Agent C) calls SafetyGate.renderSafeCard(prayer) before
//        rendering PrayerFollowUpCard; if a non-null result is returned, render that
//      - TenderCard may appear inside the arc (tender items are not arc-blocked)
//
// [F3] DoctrinalHumilityNote
//      - Appended to every AI-generated reflection block in VerseReflectionCard
//        and any future AI-reflection surface
//      - No exceptions; do not wrap in a feature flag
//
// [F4] ConsentRow
//      - Used in BereanOnboarding (Agent B) IntegrationsConsentScreen
//      - Used in any Settings surface that toggles a Berean integration
//      - enabled prop must always be initialised false at call site
//
// [F5] SafetyGate
//      - Check isSafeToReflect() before calling any AI reflection generator
//      - Check isBlockedFromArc() before pushing a card into ArcCardStack
//      - renderSafeCard() is the single authoritative router for non-normal items
//
// [F6] WhySeeingThisSheet
//      - BereanFeed (Agent C) calls onWhySeeingThis(card) which enriches the card
//        with card.whyExplanation; pass that to WhySeeingThisSheet as `explanation`
//      - Every card in the feed MUST have a "Why am I seeing this?" button
//      - Crisis cards are the only exception: they do not expose a "Why" button
