/**
 * churchIntelligenceFunctions.js
 * Find a Church Intelligence Layer — Cloud Functions
 * AMEN App
 *
 * Exports:
 *  1. createOrUpdateVisitSession    — callable, auth required, state machine validated
 *  2. saveChurchReflection          — callable, auth required, text validated
 *  3. handlePostVisitPromptEligibility — callable, dismissal/cooldown check
 *  4. buildChurchVisitInsights      — onWrite trigger, aggregates visit data
 *  5. churchPromptPolicyCheck       — callable, server-side policy mirror
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Avoid double-init if included alongside functionsindex.js
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// =============================================================================
// HELPERS
// =============================================================================

/**
 * Validates that a state transition is legal according to the visit state machine.
 * Mirrors ChurchVisitSessionManager.isValidTransition on the client.
 */
function isValidStateTransition(from, to) {
  const validTransitions = {
    none:             ['planning', 'arrived'],
    planning:         ['arrived'],
    arrived:          ['inService', 'postVisit'],
    inService:        ['postVisit'],
    postVisit:        ['revisitSuggested', 'none'],
    revisitSuggested: ['none', 'planning'],
  };
  return (validTransitions[from] || []).includes(to);
}

/**
 * Returns true if the given date is today (same calendar day, UTC).
 */
function isToday(timestamp) {
  if (!timestamp) return false;
  const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
  const now = new Date();
  return (
    date.getUTCFullYear() === now.getUTCFullYear() &&
    date.getUTCMonth() === now.getUTCMonth() &&
    date.getUTCDate() === now.getUTCDate()
  );
}

/**
 * Returns the number of hours between two dates.
 */
function hoursBetween(dateA, dateB) {
  const msA = dateA instanceof Date ? dateA.getTime() : dateA.toDate().getTime();
  const msB = dateB instanceof Date ? dateB.getTime() : dateB.toDate().getTime();
  return Math.abs(msA - msB) / (1000 * 60 * 60);
}

// =============================================================================
// 1. createOrUpdateVisitSession
// =============================================================================

/**
 * Callable: Creates or updates a church visit session with state machine validation.
 *
 * Request body:
 *   {
 *     sessionId: string (optional — omit to create new),
 *     churchId: string,
 *     toState: ChurchVisitState,
 *     metadata: object (optional — e.g. arrivedAt, dwellDurationSeconds)
 *   }
 *
 * Returns: { sessionId, state }
 */
exports.createOrUpdateVisitSession = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const userId = context.auth.uid;
  const { sessionId, churchId, toState, metadata = {} } = data;

  if (!churchId || typeof churchId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'churchId is required.');
  }
  if (!toState || typeof toState !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'toState is required.');
  }

  const validStates = ['none', 'planning', 'arrived', 'inService', 'postVisit', 'revisitSuggested'];
  if (!validStates.includes(toState)) {
    throw new functions.https.HttpsError('invalid-argument', `Invalid state: ${toState}`);
  }

  const sessionsRef = db.collection('users').doc(userId).collection('churchVisitSessions');

  // Deduplicate or create
  let sessionRef;
  let fromState = 'none';

  if (sessionId) {
    sessionRef = sessionsRef.doc(sessionId);
    const existing = await sessionRef.get();
    if (existing.exists) {
      fromState = existing.data().state || 'none';
      // Dedupe: if already in the target state, return early
      if (fromState === toState) {
        return { sessionId: sessionId, state: toState, deduplicated: true };
      }
      if (!isValidStateTransition(fromState, toState)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          `Invalid state transition: ${fromState} → ${toState}`
        );
      }
    }
  } else {
    sessionRef = sessionsRef.doc();
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const sessionData = {
    churchId,
    userId,
    state: toState,
    updatedAt: now,
    ...metadata,
  };

  if (!sessionId) {
    // New session
    sessionData.createdAt = now;
    sessionData.noteIds = [];
    sessionData.isPrivate = true;
    sessionData.arrivalConfidence = metadata.arrivalConfidence || 0;
    sessionData.serviceConfidence = metadata.serviceConfidence || 0;
    sessionData.exitConfidence = metadata.exitConfidence || 0;
  }

  await sessionRef.set(sessionData, { merge: true });

  functions.logger.info(`[VisitSession] ${userId}: ${fromState} → ${toState} for church ${churchId}`);
  return { sessionId: sessionRef.id, state: toState };
});

// =============================================================================
// 2. saveChurchReflection
// =============================================================================

/**
 * Callable: Saves a church reflection draft after validating content.
 *
 * Request body:
 *   {
 *     churchId: string,
 *     visitSessionId: string (optional),
 *     takeawayText: string (required, non-empty, max 2000 chars),
 *     scriptureText: string (optional),
 *     prayerText: string (optional),
 *     shareTarget: string (optional — "openTable" etc.),
 *     isPrivate: boolean
 *   }
 *
 * Returns: { reflectionId }
 */
exports.saveChurchReflection = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const userId = context.auth.uid;
  const {
    churchId,
    visitSessionId,
    takeawayText,
    scriptureText,
    prayerText,
    shareTarget,
    isPrivate = true,
  } = data;

  // Validate takeaway
  if (!takeawayText || typeof takeawayText !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'takeawayText is required.');
  }
  const trimmed = takeawayText.trim();
  if (trimmed.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'takeawayText cannot be empty.');
  }
  if (trimmed.length > 2000) {
    throw new functions.https.HttpsError('invalid-argument', 'takeawayText exceeds 2000 character limit.');
  }
  if (!churchId || typeof churchId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'churchId is required.');
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const reflectionRef = db.collection('users').doc(userId).collection('churchReflections').doc();

  const reflectionData = {
    id: reflectionRef.id,
    userId,
    churchId,
    visitSessionId: visitSessionId || null,
    takeawayText: trimmed,
    scriptureText: scriptureText ? scriptureText.trim() : null,
    prayerText: prayerText ? prayerText.trim() : null,
    shareTarget: shareTarget || null,
    isPrivate: Boolean(isPrivate),
    createdAt: now,
    updatedAt: now,
  };

  await reflectionRef.set(reflectionData);

  // If linked to a session, update the session's reflectionId
  if (visitSessionId) {
    await db
      .collection('users').doc(userId)
      .collection('churchVisitSessions').doc(visitSessionId)
      .update({ reflectionId: reflectionRef.id, updatedAt: now });
  }

  functions.logger.info(`[Reflection] Saved reflection ${reflectionRef.id} for user ${userId}`);
  return { reflectionId: reflectionRef.id };
});

// =============================================================================
// 3. handlePostVisitPromptEligibility
// =============================================================================

/**
 * Callable: Checks whether a post-visit prompt should be shown.
 * Server-authoritative version of client-side eligibility checks.
 *
 * Request body:
 *   {
 *     promptType: ChurchAssistPromptType
 *   }
 *
 * Returns: { shouldShow: boolean, promptType: string, reason?: string }
 */
exports.handlePostVisitPromptEligibility = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const userId = context.auth.uid;
  const { promptType } = data;

  if (!promptType) {
    throw new functions.https.HttpsError('invalid-argument', 'promptType is required.');
  }

  // Load user's assist state
  const assistStateSnap = await db
    .collection('users').doc(userId)
    .collection('churchAssistState').doc('current')
    .get();

  if (!assistStateSnap.exists) {
    return { shouldShow: true, promptType, reason: 'No assist state — first run' };
  }

  const assistState = assistStateSnap.data();

  // Check global enabled
  if (assistState.enabled === false) {
    return { shouldShow: false, promptType, reason: 'Church assist disabled' };
  }

  // Check post-visit permission
  if (!assistState.allowPostVisitPrompts) {
    return { shouldShow: false, promptType, reason: 'Post-visit prompts disabled' };
  }

  // Check dismissal history with 24h cooldown
  const dismissed = assistState.dismissedPromptTypes || [];
  if (dismissed.includes(promptType)) {
    const lastPromptAt = assistState.lastPromptAt;
    if (lastPromptAt && hoursBetween(lastPromptAt.toDate(), new Date()) < 24) {
      return { shouldShow: false, promptType, reason: 'Recently dismissed' };
    }
  }

  // Check daily limit (max 2 prompts/day)
  const lastPromptAt = assistState.lastPromptAt;
  if (lastPromptAt && isToday(lastPromptAt)) {
    // Count prompts shown today from a subcollection (simplified: check promptCount field)
    const promptCount = assistState.dailyPromptCount || 1;
    if (promptCount >= 2) {
      return { shouldShow: false, promptType, reason: 'Daily limit reached' };
    }
  }

  functions.logger.info(`[PromptEligibility] Eligible for ${promptType} — user ${userId}`);
  return { shouldShow: true, promptType };
});

// =============================================================================
// 4. buildChurchVisitInsights
// =============================================================================

/**
 * Firestore trigger: Runs when a church visit session is written.
 * Aggregates visit stats and updates the user's insights summary doc.
 */
exports.buildChurchVisitInsights = functions.firestore
  .document('users/{userId}/churchVisitSessions/{sessionId}')
  .onWrite(async (change, context) => {
    const { userId } = context.params;

    try {
      // Gather all sessions for this user
      const sessionsSnap = await db
        .collection('users').doc(userId)
        .collection('churchVisitSessions')
        .orderBy('createdAt', 'desc')
        .limit(200)
        .get();

      if (sessionsSnap.empty) return null;

      const sessions = sessionsSnap.docs.map(d => d.data());

      // Total visits (postVisit or later states)
      const completedSessions = sessions.filter(s =>
        ['postVisit', 'revisitSuggested'].includes(s.state)
      );
      const totalVisits = completedSessions.length;

      // Favorite church IDs (top 3 by visit count)
      const churchVisitCounts = {};
      for (const s of completedSessions) {
        if (s.churchId) {
          churchVisitCounts[s.churchId] = (churchVisitCounts[s.churchId] || 0) + 1;
        }
      }
      const favoriteChurchIds = Object.entries(churchVisitCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([id]) => id);

      // Last visited church
      const lastSession = completedSessions[0];
      const lastVisitedChurchId = lastSession ? lastSession.churchId : null;
      const lastVisitAt = lastSession ? (lastSession.exitedAt || lastSession.arrivedAt || lastSession.createdAt) : null;

      // Common service times (simplified — extract hour from arrivedAt)
      const hourCounts = {};
      for (const s of completedSessions) {
        const arrivedAt = s.arrivedAt ? s.arrivedAt.toDate() : null;
        if (arrivedAt) {
          const hour = arrivedAt.getHours();
          const label = hour < 12
            ? 'Sunday mornings'
            : hour < 17
              ? 'Sunday afternoons'
              : 'Sunday evenings';
          hourCounts[label] = (hourCounts[label] || 0) + 1;
        }
      }
      const commonServiceTimes = Object.entries(hourCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 2)
        .map(([label]) => label);

      const insightsData = {
        totalVisits,
        favoriteChurchIds,
        commonServiceTimes,
        lastVisitedChurchId: lastVisitedChurchId || null,
        lastVisitAt: lastVisitAt || null,
        topReflectionThemes: [], // Populated by a separate NLP job
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db
        .collection('users').doc(userId)
        .collection('churchVisitInsights').doc('summary')
        .set(insightsData, { merge: true });

      functions.logger.info(`[Insights] Updated insights for user ${userId}: ${totalVisits} visits`);
      return null;
    } catch (error) {
      functions.logger.error(`[Insights] Error building insights for user ${userId}:`, error);
      return null;
    }
  });

// =============================================================================
// 5. churchPromptPolicyCheck
// =============================================================================

/**
 * Callable: Server-side mirror of ChurchPromptPolicyEngine.
 * Authoritative prompt policy check for sensitive or high-value surfaces.
 *
 * Request body:
 *   {
 *     promptType: ChurchAssistPromptType,
 *     currentVisitState: ChurchVisitState (optional)
 *   }
 *
 * Returns: ChurchPromptDecision { shouldShow, suppressReason, prompt }
 */
exports.churchPromptPolicyCheck = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const userId = context.auth.uid;
  const { promptType, currentVisitState } = data;

  if (!promptType) {
    throw new functions.https.HttpsError('invalid-argument', 'promptType is required.');
  }

  // Load assist state
  const assistStateSnap = await db
    .collection('users').doc(userId)
    .collection('churchAssistState').doc('current')
    .get();

  const assistState = assistStateSnap.exists ? assistStateSnap.data() : { enabled: true };

  // --- Rule 1: Global enable ---
  if (assistState.enabled === false) {
    return { shouldShow: false, suppressReason: 'Church assist disabled', prompt: promptType };
  }

  // --- Rule 2: Location prompts ---
  const locationRequiredTypes = ['arrivedNeedsNotes', 'arrivedChecklist', 'inServiceCaptureVerse', 'inServicePrayerThought', 'firstVisitCompanion'];
  if (locationRequiredTypes.includes(promptType) && !assistState.allowLocationPrompts) {
    return { shouldShow: false, suppressReason: 'Location prompts not allowed', prompt: promptType };
  }

  // --- Rule 3: Dismissal cooldown ---
  const dismissed = assistState.dismissedPromptTypes || [];
  if (dismissed.includes(promptType)) {
    const lastPromptAt = assistState.lastPromptAt;
    if (!lastPromptAt || hoursBetween(lastPromptAt.toDate(), new Date()) < 24) {
      return { shouldShow: false, suppressReason: 'Recently dismissed', prompt: promptType };
    }
  }

  // --- Rule 4: Post-visit permission ---
  const postVisitTypes = ['postVisitReflection', 'postVisitShare', 'revisitSuggestion'];
  if (postVisitTypes.includes(promptType) && !assistState.allowPostVisitPrompts) {
    return { shouldShow: false, suppressReason: 'Post-visit prompts disabled', prompt: promptType };
  }

  // --- Rule 5: Service mode permission ---
  const serviceModeTypes = ['inServiceCaptureVerse', 'inServicePrayerThought'];
  if (serviceModeTypes.includes(promptType) && !assistState.allowServiceMode) {
    return { shouldShow: false, suppressReason: 'Service mode disabled', prompt: promptType };
  }

  // --- Rule 6: Daily limit ---
  const lastPromptAt = assistState.lastPromptAt;
  if (lastPromptAt && isToday(lastPromptAt)) {
    const dailyCount = assistState.dailyPromptCount || 1;
    if (dailyCount >= 2) {
      return { shouldShow: false, suppressReason: 'Daily limit reached', prompt: promptType };
    }
  }

  // --- Rule 7: Arrived prompts — only once per session ---
  const arrivedOnlyTypes = ['arrivedNeedsNotes', 'arrivedChecklist'];
  if (arrivedOnlyTypes.includes(promptType)) {
    const resolvedState = currentVisitState || assistState.currentVisitState;
    const pastArrived = ['inService', 'postVisit', 'revisitSuggested'];
    if (pastArrived.includes(resolvedState)) {
      return { shouldShow: false, suppressReason: 'Arrived prompt already shown this session', prompt: promptType };
    }
  }

  functions.logger.info(`[PolicyCheck] Approved '${promptType}' for user ${userId}`);
  return { shouldShow: true, suppressReason: null, prompt: promptType };
});
