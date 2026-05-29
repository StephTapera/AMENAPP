// globalCircuitBreaker.js
// Checks and increments a global daily AI spend counter.
// Returns void — throws HttpsError('resource-exhausted') if over budget.
// Stored at Firestore: meta/globalAICosts/daily/{YYYY-MM-DD}
//
// Budget per service (calls/day):
//   anthropic: 2000  (bereanChatProxy + anonymousBereanQuery + aiPromptFeatures)
//   openai:    5000  (openAIProxy + whisperProxy + smartSuggestionsProxy)
//   pinecone: 10000  (semanticEmbeddings)
//
// Config can be overridden at Firestore doc: config/aiLimits
//   Fields: anthropicDailyGlobalCap, openaiDailyGlobalCap, pineconeDailyGlobalCap

'use strict';

const admin = require('firebase-admin');
const { logger } = require('firebase-functions');

const DEFAULT_CAPS = {
  anthropic: 2000,
  openai: 5000,
  pinecone: 10000,
};

/**
 * Check and increment global daily call counter for a service.
 * Fails OPEN on Firestore errors so a config outage never blocks users.
 * Re-throws HttpsErrors so legitimate cap hits propagate to callers.
 *
 * @param {'anthropic'|'openai'|'pinecone'} service
 * @returns {Promise<void>} — throws HttpsError('resource-exhausted') if over cap
 */
async function checkGlobalCircuitBreaker(service) {
  const { HttpsError } = require('firebase-functions/v2/https');
  const db = admin.firestore();
  const dayKey = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"

  try {
    const [configSnap, dailySnap] = await Promise.all([
      db.doc('config/aiLimits').get(),
      db.doc(`meta/globalAICosts/daily/${dayKey}`).get(),
    ]);

    const capField = `${service}DailyGlobalCap`;
    const cap = (configSnap.exists && configSnap.data()[capField] != null)
      ? configSnap.data()[capField]
      : DEFAULT_CAPS[service];

    const current = (dailySnap.exists && dailySnap.data()[`${service}Calls`] != null)
      ? dailySnap.data()[`${service}Calls`]
      : 0;

    if (current >= cap) {
      logger.warn('[circuitBreaker] daily cap reached', { service, current, cap, dayKey });
      throw new HttpsError(
        'resource-exhausted',
        'Service is temporarily at capacity. Please try again later.',
      );
    }

    // Increment atomically
    await db.doc(`meta/globalAICosts/daily/${dayKey}`).set(
      {
        [`${service}Calls`]: admin.firestore.FieldValue.increment(1),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (err) {
    // Re-throw HttpsErrors (cap hit or other functional error)
    if (err.code !== undefined) throw err;
    // Fail OPEN on transient Firestore errors — a config outage must not
    // silently block every AI request for every user.
    logger.error(`[circuitBreaker] check failed for ${service}, proceeding`, err);
  }
}

module.exports = { checkGlobalCircuitBreaker };
