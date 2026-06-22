/**
 * integrate.ts — Sabbath Mode Feature Integration
 * Final Wiring & Verification Agent
 * Date: 2026-06-07
 *
 * SINGLE WIRING POINT — shows how all Sabbath Mode pieces connect.
 *
 * HOW TO MOUNT IN THE ROOT APP:
 * ─────────────────────────────────────────────────────────────────
 * 1. Wrap the app root with <SabbathProvider uid={currentUser.uid} db={firestoreDb}>
 *    (import from './engine')
 *
 * 2. Wrap the router with <SabbathRouteGuard currentRoute={currentRoute} uid={uid}
 *      onSurfaceSelect={handleSurfaceSelect} onStepOut={handleStepOut}>
 *    (import from './engine')
 *
 * 3. On app init: call the `evaluateSabbathMode` Firebase callable to sync state:
 *      const fn = httpsCallable(functions, 'evaluateSabbathMode');
 *      await fn({});   // uid defaults to caller's uid server-side
 *
 * 4. To show the Berean Guide for a surface:
 *    <SabbathBereanGuide task="sabbath_guide" uid={uid} onClose={handleClose} />
 *    (import from './berean')
 *
 * 5. To show the Re-entry Digest on return from Sabbath:
 *    <ReEntryDigestView digest={digest} onReflectionSubmit={handleSave} onDismiss={dismiss} />
 *    (import from './ui')
 * ─────────────────────────────────────────────────────────────────
 */

// ── Contract imports ──────────────────────────────────────────────────────────
import type {
  SabbathDay,
  SabbathState,
  SabbathBoundary,
  SabbathSurface,
  SabbathConfig,
  SabbathSession,
  SabbathReflection,
  SabbathDigest,
  SabbathConfigDefaults,
  SabbathRouteGuardContract,
  SabbathAITask,
} from './contracts';

import {
  sabbathConfig,
  SABBATH_ALWAYS_ALLOWED,
  SABBATH_AI_TASKS,
} from './contracts';

// ── Engine imports ─────────────────────────────────────────────────────────────
import {
  computeSabbathState,
  getLocalDateString,
  buildSessionKey,
  canStepOut,
  SabbathProvider,
  SabbathStepOutError,
  useSabbath,
  SabbathRouteGuard,
} from './engine';

export type {
  SabbathContextValue,
  SabbathProviderProps,
  SabbathRouteGuardProps,
} from './engine';

// ── UI imports ─────────────────────────────────────────────────────────────────
import { SabbathWindowView } from './ui/SabbathWindowView';
import { SabbathSurfaceList } from './ui/SabbathSurfaceList';
import { BlessAndCloseSheet } from './ui/BlessAndCloseSheet';
import { ReEntryDigestView } from './ui/ReEntryDigestView';
import { SabbathBanner } from './ui/SabbathBanner';
import { SolidarityPresence } from './ui/SolidarityPresence';
import { SabbathTokens } from './ui/SabbathTokens';

// ── Berean imports ─────────────────────────────────────────────────────────────
import { callSabbathModel } from './berean/callSabbathModel';
import { SabbathBereanGuide } from './berean/SabbathBereanGuide';
import { getLiturgicalContext } from './berean/liturgicalSeason';
import {
  buildSabbathGuidePrompt,
  buildFamilyQuestionsPrompt,
  buildSermonPrepPrompt,
  buildDevotionalPrompt,
  buildReflectionPrompt,
} from './berean/sabbathPrompts';

export type { LiturgicalSeason, LiturgicalContext } from './berean';
export type { PromptContext, SabbathModelRequest, SabbathModelResponse } from './berean';

// ── Re-exports for convenience ────────────────────────────────────────────────

// Contracts
export type {
  SabbathDay,
  SabbathState,
  SabbathBoundary,
  SabbathSurface,
  SabbathConfig,
  SabbathSession,
  SabbathReflection,
  SabbathDigest,
  SabbathConfigDefaults,
  SabbathRouteGuardContract,
  SabbathAITask,
};
export { sabbathConfig, SABBATH_ALWAYS_ALLOWED, SABBATH_AI_TASKS };

// Engine
export {
  computeSabbathState,
  getLocalDateString,
  buildSessionKey,
  canStepOut,
  SabbathProvider,
  SabbathStepOutError,
  useSabbath,
  SabbathRouteGuard,
};

// UI
export {
  SabbathWindowView,
  SabbathSurfaceList,
  BlessAndCloseSheet,
  ReEntryDigestView,
  SabbathBanner,
  SolidarityPresence,
  SabbathTokens,
};

// Berean
export {
  callSabbathModel,
  SabbathBereanGuide,
  getLiturgicalContext,
  buildSabbathGuidePrompt,
  buildFamilyQuestionsPrompt,
  buildSermonPrepPrompt,
  buildDevotionalPrompt,
  buildReflectionPrompt,
};

// ── Feature manifest ───────────────────────────────────────────────────────────

/**
 * SabbathFeature — canonical feature manifest.
 *
 * This object documents the full wiring of Sabbath Mode v1.0.0 and is the
 * single source of truth for deploy commands, open human decisions, and the
 * non-negotiable invariant list.
 *
 * It is intentionally a plain object (not a class) so it can be logged,
 * serialised, and inspected at runtime without side effects.
 */
export const SabbathFeature = {
  version: '1.0.0',
  buildDate: '2026-06-07',

  // ── Mount instructions ─────────────────────────────────────────────────────
  //
  // 1. Wrap app root:
  //      <SabbathProvider uid={currentUser.uid} db={firestoreDb}>
  //        <App />
  //      </SabbathProvider>
  //
  // 2. Wrap router (inside SabbathProvider):
  //      <SabbathRouteGuard
  //        currentRoute={currentRoute}
  //        uid={uid}
  //        onSurfaceSelect={handleSurfaceSelect}
  //        onStepOut={handleStepOut}
  //      >
  //        {children}
  //      </SabbathRouteGuard>
  //
  // 3. On app init — call evaluateSabbathMode to prime Firestore state:
  //      const fn = httpsCallable(functions, 'evaluateSabbathMode');
  //      const { data } = await fn({});
  //      // data: { state, config, session, digest? }
  //
  // 4. Surface-routing inside onSurfaceSelect:
  //      'scripture'        → your scripture reader
  //      'prayer'           → your prayer surface
  //      'bereanGuide'      → <SabbathBereanGuide task="sabbath_guide" uid={uid} />
  //      'churchNotes'      → your church notes surface
  //      'findChurch'       → your Find a Church surface
  //      'spaces'           → your Spaces hub
  //      'familyQuestions'  → <SabbathBereanGuide task="family_questions" uid={uid} />
  //      'reflection'       → <SabbathBereanGuide task="reflection_prompt" uid={uid} />
  //                        OR your own text input wired to SabbathReflection Firestore doc
  //
  // 5. Re-entry digest — shown once after Sabbath ends:
  //      evaluateSabbathMode returns digest when digestShown is false.
  //      <ReEntryDigestView
  //        digest={digest}
  //        onReflectionSubmit={body => saveReflection(uid, body)}
  //        onDismiss={() => setDigestShown(true)}
  //      />

  // ── Module wiring ──────────────────────────────────────────────────────────
  contracts: {
    sabbathConfig,
    SABBATH_ALWAYS_ALLOWED,
    SABBATH_AI_TASKS,
  },

  engine: {
    computeSabbathState,
    getLocalDateString,
    buildSessionKey,
    canStepOut,
    SabbathProvider,
    SabbathRouteGuard,
    useSabbath,
    SabbathStepOutError,
  },

  ui: {
    SabbathWindowView,
    SabbathSurfaceList,
    BlessAndCloseSheet,
    ReEntryDigestView,
    SabbathBanner,
    SolidarityPresence,
    SabbathTokens,
  },

  berean: {
    callSabbathModel,
    SabbathBereanGuide,
    getLiturgicalContext,
  },

  // ── Backend callables (deploy these via Firebase CLI) ─────────────────────
  backendCallables: [
    'evaluateSabbathMode',       // HTTPS callable — evaluates + primes Firestore state
    'setSabbathPreference',      // HTTPS callable — updates users/{uid}/sabbath/config
    'syncFamilySabbathPresence', // HTTPS callable — boolean-only family presence sync
  ] as const,

  // ── Firestore triggers (deployed alongside callables) ─────────────────────
  backendTriggers: [
    'onSabbathNotificationWrite', // Firestore trigger — batcher on users/{uid}/notifications/{notifId}
  ] as const,

  // ── Deploy commands (exact CLI strings — copy-paste ready) ────────────────
  deploySteps: [
    // 1. Deploy all four Sabbath Cloud Functions at once
    'cd Backend/functions && firebase deploy --only functions:evaluateSabbathMode,functions:setSabbathPreference,functions:syncFamilySabbathPresence,functions:onSabbathNotificationWrite --project amen-5e359',
    // 2. Deploy updated Firestore security rules
    'firebase deploy --only firestore:rules --project amen-5e359',
  ] as const,

  // ── Open human decisions (expected stops — not failures) ──────────────────
  openHumanDecisions: [
    'COPY_SIGNOFF: BlessAndCloseSheet.tsx — Option A (gentle) vs Option B (liturgical). ' +
      'Option A is currently active. See file header for both options.',

    'MINOR_GATE: Minor-account inclusion in family/Space Sabbath presence requires human ' +
      'approval before familySabbathSync callable can process minors. Currently the callable ' +
      'returns { MINOR_GATE_REQUIRED: true } and writes nothing when any member is a minor. ' +
      'Human decision: define the approved UX for minor presence before relaxing this gate.',

    'CHILD_SAFETY_STUB: ChildSafetyAgentStubView is pending App Store & legal approval. ' +
      'Route "child_safety_report" is reserved in SABBATH_ALWAYS_ALLOWED but points to ' +
      'GatedAgentStubViews.swift:ChildSafetyAgentStubView. Update when the live flow is approved.',
  ] as const,

  // ── Non-negotiable invariant confirmation ─────────────────────────────────
  nonNegotiables: {
    'NO_INLINE_ROUTE_IDS':      'CONFIRMED — SabbathRouteGuard imports SABBATH_ALWAYS_ALLOWED from contracts',
    'SAFETY_ALWAYS_ALLOWED':    'CONFIRMED — emergency_support, trusted_circle, child_safety_report pass gate',
    'FAIL_CLOSED_AI':           'CONFIRMED — callSabbathModel has no fallover; graceful error on exhaustion',
    'NO_BADGE_COUNTS':          'CONFIRMED — notificationBatcher and digestBuilder never write counts',
    'SHOW_ONCE_DIGEST':         'CONFIRMED — digestShown flag in Firestore; buildDigest returns null if already shown',
    'MINOR_GATE':               'CONFIRMED — all three backend callables check isMinor / ageTier before writes',
    'NO_GOLD_PURPLE_DARK':      'CONFIRMED — SabbathTokens uses only neutral #F7F7F7 / #FFFFFF / black palette',
    'NO_SERIF_FONT':            'CONFIRMED — fontStack is SF Pro Display / system sans-serif only',
    'STEP_OUT_CONFIRM_REQUIRED':'CONFIRMED — BlessAndCloseSheet shown before enterStepOut; confirmed=true enforced',
    'MAX_STEP_OUT_1':           'CONFIRMED — canStepOut returns false if steppedOutAt is already set',
  } as const,
} as const;
