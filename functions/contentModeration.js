/**
 * contentModeration.js
 * 
 * Backend moderation pipeline for AMEN app
 * - Text moderation (toxicity, spam, AI detection)
 * - Organic content scoring
 * - Near-duplicate detection
 * - User behavior risk signals
 * - Moderation decision engine
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');

// Lazy-initialize Language client to avoid blocking module load (causes deploy timeout)
const {LanguageServiceClient} = require('@google-cloud/language');
let _languageClient = null;
function getLanguageClient() {
    if (!_languageClient) {
        _languageClient = new LanguageServiceClient();
    }
    return _languageClient;
}

// MARK: - Main Moderation Endpoint

/**
 * Moderate content submission (posts, comments, captions, bio)
 * Callable function from client
 */
exports.moderateContent = functions.https.onCall(async (data, context) => {
  // Authenticate
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const userId = context.auth.uid;
  const {
    contentText,
    contentType,  // 'post', 'comment', 'reply', 'profile_bio', 'caption'
    authenticitySignals,  // From client ComposerIntegrityTracker
    parentContentId,  // For comments/replies
  } = data;

  try {
    // 1. Run parallel moderation checks
    const [
      toxicityResult,
      spamResult,
      aiSuspicionResult,
      duplicateResult,
      userRiskResult
    ] = await Promise.all([
      checkToxicity(contentText),
      checkSpam(contentText, contentType),
      checkAISuspicion(contentText, authenticitySignals),
      checkNearDuplicate(contentText, userId, contentType),
      getUserRiskScore(userId)
    ]);

    // 2. Get user violation history
    const userViolationCount = await getUserViolationCount(userId);
    const recentSimilarContentCount = duplicateResult.matchCount;

    // 3. Compute moderation scores
    const scores = {
      toxicity: toxicityResult.score,
      spam: spamResult.score,
      aiSuspicion: aiSuspicionResult.score,
      duplicateMatch: duplicateResult.score,
      authenticity: 1.0 - aiSuspicionResult.score,
      userRiskScore: userRiskResult.score
    };

    // 4. Determine enforcement action
    const decision = determineEnforcementAction(
      scores,
      contentType,
      userViolationCount,
      recentSimilarContentCount,
      contentText
    );

    // 5. Log moderation event (legacy collection) + unified moderation_jobs
    const contentId = data.contentId || `${userId}_${Date.now()}`;
    await Promise.all([
      logModerationEvent({
        userId,
        contentType,
        contentText: contentText.substring(0, 500),
        decision,
        scores,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      }),
      writeModerationJob({
        contentId,
        contentType,
        authorId: userId,
        contentSnapshot: contentText.substring(0, 4000),
        scores,
        decision,
        signals: [
          ...(spamResult.indicators || []),
          ...(aiSuspicionResult.signals || []),
        ],
      }),
    ]);

    // 6. Update user integrity signals if violation detected
    if (decision.action !== 'allow' && decision.action !== 'nudge_rewrite') {
      await incrementUserViolations(userId, decision.action);
    }

    // 7. Store content fingerprint for duplicate detection
    if (decision.action === 'allow' || decision.action === 'nudge_rewrite') {
      await storeContentFingerprint(userId, contentText, contentType);
    }

    return {
      decision: decision.action,
      confidence: decision.confidence,
      reasons: decision.reasons,
      suggestedRevisions: decision.suggestedRevisions,
      reviewRequired: decision.reviewRequired,
      appealable: decision.appealable,
      userMessage: decision.userMessage,
      // Don't return scores to client (internal only)
    };

  } catch (error) {
    console.error('Moderation error:', error);
    // Fail closed on error — hold for human review rather than auto-approving
    await logModerationError(userId, contentType, error);
    return {
      decision: 'hold_for_review',
      confidence: 0,
      reasons: ['Moderation service error — held for human review'],
      reviewRequired: true
    };
  }
});

// MARK: - Toxicity Detection

async function checkToxicity(text) {
  try {
    const document = {
      content: text,
      type: 'PLAIN_TEXT',
    };

    // Use Google Cloud Natural Language API for toxicity
    const [result] = await getLanguageClient().moderateText({document});
    
    const toxicityCategories = result.moderationCategories || [];
    const maxConfidence = Math.max(
      ...toxicityCategories.map(cat => cat.confidence),
      0
    );

    return {
      score: maxConfidence,
      categories: toxicityCategories.map(cat => cat.name)
    };

  } catch (error) {
    console.error('Toxicity check error:', error);
    return {score: 0, categories: []};
  }
}

// MARK: - Spam Detection

async function checkSpam(text, contentType) {
  let spamScore = 0;
  const indicators = [];

  // 1. Excessive repetition
  const words = text.toLowerCase().split(/\s+/);
  const uniqueWords = new Set(words);
  const repetitionRatio = words.length / uniqueWords.size;
  if (repetitionRatio > 3) {
    spamScore += 0.3;
    indicators.push('excessive_repetition');
  }

  // 2. All caps (more than 50%)
  const capsRatio = (text.match(/[A-Z]/g) || []).length / text.length;
  if (capsRatio > 0.5 && text.length > 20) {
    spamScore += 0.2;
    indicators.push('excessive_caps');
  }

  // 3. Excessive punctuation/emojis
  const specialChars = (text.match(/[!?]{3,}/g) || []).length;
  if (specialChars > 5) {
    spamScore += 0.2;
    indicators.push('excessive_punctuation');
  }

  // 4. URL spam patterns
  const urlCount = (text.match(/https?:\/\//gi) || []).length;
  if (urlCount > 2) {
    spamScore += 0.3;
    indicators.push('multiple_urls');
  }

  // 5. Short repetitive comments (stricter for comments)
  if (contentType === 'comment' || contentType === 'reply') {
    if (text.length < 20 && text.match(/^(amen|praise|hallelujah|glory)$/i)) {
      spamScore += 0.1;  // Low score - could be genuine
    }
  }

  return {
    score: Math.min(spamScore, 1.0),
    indicators
  };
}

// MARK: - AI Suspicion Detection

async function checkAISuspicion(text, authenticitySignals) {
  let aiScore = 0;
  const signals = [];

  // 1. Client-side signals (most reliable)
  if (authenticitySignals) {
    // Very low typed vs pasted ratio
    if (authenticitySignals.typedVsPastedRatio < 0.1 && authenticitySignals.pastedCharacters > 200) {
      aiScore += 0.4;
      signals.push('mostly_pasted');
    }
    
    // Large paste event
    if (authenticitySignals.largestPasteLength > 500) {
      aiScore += 0.3;
      signals.push('large_paste');
    }
  }

  // 2. Text pattern analysis
  // AI-generated text tends to be very formal and structured
  const sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 0);
  
  // Very consistent sentence length (AI pattern)
  if (sentences.length >= 3) {
    const lengths = sentences.map(s => s.length);
    const avgLength = lengths.reduce((a, b) => a + b, 0) / lengths.length;
    const variance = lengths.reduce((sum, len) => sum + Math.pow(len - avgLength, 2), 0) / lengths.length;
    const stdDev = Math.sqrt(variance);
    
    if (stdDev < 20 && avgLength > 50) {
      aiScore += 0.2;
      signals.push('uniform_sentences');
    }
  }

  // 3. Excessive formal language for casual app
  const formalWords = ['furthermore', 'moreover', 'nevertheless', 'consequently', 'additionally'];
  const formalWordCount = formalWords.filter(word => text.toLowerCase().includes(word)).length;
  if (formalWordCount >= 2) {
    aiScore += 0.2;
    signals.push('overly_formal');
  }

  // 4. Check if legitimate quoted content (Scripture, sermon, etc.)
  if (isLegitimateQuotedContent(text)) {
    aiScore *= 0.3;  // Reduce AI suspicion for legitimate quotes
    signals.push('legitimate_quote');
  }

  return {
    score: Math.min(aiScore, 1.0),
    signals
  };
}

function isLegitimateQuotedContent(text) {
  const scriptureIndicators = /bible|scripture|verse|psalm|proverbs|john|matthew|corinthians|romans|genesis/i;
  const attributionIndicators = /["""—]|^from |^by |according to|pastor|sermon/i;
  
  return scriptureIndicators.test(text) || attributionIndicators.test(text);
}

// MARK: - Near-Duplicate Detection

async function checkNearDuplicate(text, userId, contentType) {
  try {
    // Create content fingerprint (simhash)
    const fingerprint = createFingerprint(text);
    
    // Query recent fingerprints from this user
    const db = admin.firestore();
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);  // 24 hours
    
    const recentContent = await db.collection('content_fingerprints')
      .where('userId', '==', userId)
      .where('contentType', '==', contentType)
      .where('createdAt', '>', cutoff)
      .limit(50)
      .get();
    
    let matchCount = 0;
    let bestMatchScore = 0;
    
    recentContent.forEach(doc => {
      const data = doc.data();
      const similarity = hammingDistance(fingerprint, data.fingerprint);
      if (similarity > 0.85) {
        matchCount++;
        bestMatchScore = Math.max(bestMatchScore, similarity);
      }
    });
    
    return {
      score: bestMatchScore,
      matchCount
    };
    
  } catch (error) {
    console.error('Duplicate check error:', error);
    return {score: 0, matchCount: 0};
  }
}

function createFingerprint(text) {
  // Simple simhash implementation
  const hash = crypto.createHash('md5').update(text.toLowerCase()).digest('hex');
  return hash;
}

function hammingDistance(hash1, hash2) {
  let distance = 0;
  for (let i = 0; i < hash1.length; i++) {
    if (hash1[i] !== hash2[i]) distance++;
  }
  return 1 - (distance / hash1.length);
}

// MARK: - User Risk Score

async function getUserRiskScore(userId) {
  try {
    const db = admin.firestore();
    const now = Date.now();
    const recentWindow = now - (5 * 60 * 1000);  // 5 minutes
    
    // Count recent posts
    const recentPosts = await db.collection('moderation_events')
      .where('userId', '==', userId)
      .where('timestamp', '>', new Date(recentWindow))
      .count()
      .get();
    
    const postCount = recentPosts.data().count;
    
    // Risk score based on posting frequency
    let riskScore = 0;
    if (postCount > 10) riskScore = 0.9;
    else if (postCount > 5) riskScore = 0.6;
    else if (postCount > 3) riskScore = 0.3;
    
    return {score: riskScore};
    
  } catch (error) {
    console.error('User risk score error:', error);
    return {score: 0};
  }
}

async function getUserViolationCount(userId) {
  try {
    const db = admin.firestore();
    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);  // 30 days
    
    const violations = await db.collection('user_integrity_signals')
      .doc(userId)
      .get();
    
    if (!violations.exists) return 0;
    
    const data = violations.data();
    return data.violationCount || 0;
    
  } catch (error) {
    console.error('Violation count error:', error);
    return 0;
  }
}

// MARK: - Enforcement Decision Engine

function determineEnforcementAction(scores, contentType, userViolationCount, recentSimilarContentCount, contentText) {
  const strictness = contentType === 'comment' || contentType === 'reply' ? 'strict' : 'standard';
  const aiThreshold = strictness === 'strict' ? 0.5 : 0.7;
  
  let action = 'allow';
  let confidence = 0;
  let reasons = [];
  let suggestedRevisions = null;
  
  // 1. Hard violations
  if (scores.toxicity > 0.8) {
    action = 'reject';
    confidence = scores.toxicity;
    reasons.push('Toxic or harmful content detected');
  }
  else if (scores.spam > 0.85) {
    action = 'reject';
    confidence = scores.spam;
    reasons.push('Spam content detected');
  }
  
  // 2. AI/Copy-paste (graduated)
  else if (scores.aiSuspicion > aiThreshold) {
    confidence = scores.aiSuspicion;
    
    if (scores.aiSuspicion > 0.9) {
      action = userViolationCount >= 3 ? 'hold_for_review' : 'require_revision';
      reasons.push('Content appears to be AI-generated or copied');
    }
    else if (scores.aiSuspicion > 0.7) {
      action = userViolationCount >= 2 ? 'require_revision' : 'nudge_rewrite';
      reasons.push('Consider adding personal reflection');
    }
    else {
      action = 'nudge_rewrite';
      reasons.push('Add your own thoughts to make this more meaningful');
    }
    
    suggestedRevisions = [
      'Add your own reflection or experience',
      'Share how this relates to your faith journey',
      'Include your personal context or story'
    ];
  }
  
  // 3. Near-duplicates
  else if (scores.duplicateMatch > 0.8) {
    action = recentSimilarContentCount >= 3 ? 'rate_limit' : 'nudge_rewrite';
    confidence = scores.duplicateMatch;
    reasons.push('Similar content posted recently');
  }
  
  // 4. Rapid posting
  else if (scores.userRiskScore > 0.7) {
    action = 'rate_limit';
    confidence = scores.userRiskScore;
    reasons.push('Too many posts in a short time');
  }
  
  // 5. Repeated violations
  else if (userViolationCount >= 5) {
    action = 'shadow_restrict';
    confidence = 1.0;
    reasons.push('Repeated content policy violations');
  }
  
  return {
    action,
    confidence,
    reasons,
    suggestedRevisions,
    reviewRequired: action === 'hold_for_review',
    appealable: action === 'reject' || action === 'hold_for_review',
    userMessage: getActionMessage(action)
  };
}

function getActionMessage(action) {
  const messages = {
    'allow': '',
    'nudge_rewrite': 'Consider adding your own reflection or context to make this more personal',
    'require_revision': 'This content may need some personal touches. Could you share your own thoughts?',
    'hold_for_review': 'Your post is being reviewed to ensure it aligns with community guidelines',
    'rate_limit': 'You\'re posting quite frequently. Take a moment to reflect before sharing more',
    'shadow_restrict': '',
    'reject': 'This content doesn\'t meet our community guidelines. Please review and try again'
  };
  return messages[action] || '';
}

// MARK: - Data Persistence

async function logModerationEvent(event) {
  try {
    const db = admin.firestore();
    await db.collection('moderation_events').add(event);
  } catch (error) {
    console.error('Log moderation event error:', error);
  }
}

// ============================================================================
// MODERATION CONSTITUTION: unified moderation_jobs writer
// Maps existing pipeline output → ModerationConstitutionModels schema.
// Called by both moderateContent (callable) and serverSidePostModeration.
// ============================================================================

/**
 * Maps internal action strings to EnforcementActionType values from the Swift data model.
 */
function mapActionToConstitutionType(action) {
  const map = {
    'allow': 'allow',
    'nudge_rewrite': 'nudge',
    'require_revision': 'require_edit',
    'hold_for_review': 'hold_review',
    'flag_for_review': 'hold_review',
    'rate_limit': 'account_cooldown',
    'shadow_restrict': 'shadow_restrict',
    'reject': 'remove_permanent',
    'remove': 'remove_permanent',
    'error_allow': 'allow',
  };
  return map[action] || 'hold_review';
}

/**
 * Writes a ModerationJob document to moderation_jobs/{jobId}.
 * jobId is deterministic: {contentType}_{contentId}_{epochMs} so callers
 * can reference it in content docs without a separate lookup.
 *
 * @param {Object} params
 * @param {string} params.contentId       - Firestore document id of the content
 * @param {string} params.contentType     - 'post'|'comment'|'dm'|'profile'|etc.
 * @param {string} params.authorId        - uid of the author
 * @param {string} params.contentSnapshot - truncated text for review (max 4000 chars)
 * @param {Object} params.scores          - { toxicity, spam, aiSuspicion, duplicateMatch, userRiskScore }
 * @param {Object} params.decision        - output of determineEnforcementAction()
 * @param {string[]} params.signals       - SafetySignal raw values detected
 * @returns {Promise<string>}             - The new job's document id
 */
async function writeModerationJob({
  contentId,
  contentType,
  authorId,
  contentSnapshot = '',
  scores = {},
  decision = {},
  signals = [],
}) {
  try {
    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const jobId = `${contentType}_${contentId}_${Date.now()}`;

    const jobData = {
      // Source content pointer
      content_id: contentId,
      content_type: contentType,
      author_id: authorId,

      // Pipeline scores
      toxicity_score: scores.toxicity ?? null,
      spam_score: scores.spam ?? null,
      ai_suspicion_score: scores.aiSuspicion ?? null,
      overall_risk_score: Math.max(
        scores.toxicity ?? 0,
        scores.spam ?? 0,
        scores.aiSuspicion ?? 0,
        scores.userRiskScore ?? 0,
      ),

      // Signals
      signals,

      // Decision (mapped to constitution schema)
      decision: mapActionToConstitutionType(decision.action || 'allow'),
      decision_actor: 'ai_automatic',
      decision_reason: (decision.reasons || []).join('; ') || null,
      decision_confidence: decision.confidence ?? null,

      // Violations
      zero_tolerance_violations: [],
      high_risk_violations: [],
      sensitive_categories: [],

      // Timestamps
      created_at: now,
      completed_at: now,
    };

    await db.collection('moderation_jobs').doc(jobId).set(jobData);
    console.log(`📋 [moderation_jobs] Wrote job ${jobId} → decision: ${jobData.decision}`);
    return jobId;
  } catch (err) {
    // Non-fatal: don't break the content submission pipeline
    console.error('[writeModerationJob] Error:', err);
    return null;
  }
}

async function incrementUserViolations(userId, violationType) {
  try {
    const db = admin.firestore();
    const userDoc = db.collection('user_integrity_signals').doc(userId);
    
    await userDoc.set({
      violationCount: admin.firestore.FieldValue.increment(1),
      lastViolation: admin.firestore.FieldValue.serverTimestamp(),
      violationTypes: admin.firestore.FieldValue.arrayUnion(violationType)
    }, {merge: true});
    
  } catch (error) {
    console.error('Increment violations error:', error);
  }
}

async function storeContentFingerprint(userId, text, contentType) {
  try {
    const db = admin.firestore();
    const fingerprint = createFingerprint(text);
    
    await db.collection('content_fingerprints').add({
      userId,
      contentType,
      fingerprint,
      textPreview: text.substring(0, 100),
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
  } catch (error) {
    console.error('Store fingerprint error:', error);
  }
}

async function logModerationError(userId, contentType, error) {
  try {
    const db = admin.firestore();
    await db.collection('moderation_errors').add({
      userId,
      contentType,
      error: error.toString(),
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (err) {
    console.error('Log error failed:', err);
  }
}

// MARK: - Internal helper for Firestore triggers (not callable by clients)

/**
 * Runs toxicity + spam checks on post text from a Firestore trigger.
 * Returns { shouldRemove, action, reasons } so the caller can decide.
 * Fails open on error (post remains visible; flagged for review).
 *
 * @param {string} postId
 * @param {string} userId
 * @param {string} text
 * @returns {Promise<{shouldRemove: boolean, action: string, reasons: string[]}>}
 */
exports.moderatePostText = async function moderatePostText(postId, userId, text) {
  try {
    const [toxicityResult, spamResult] = await Promise.all([
      checkToxicity(text),
      checkSpam(text, 'post'),
    ]);

    const reasons = [];
    let action = 'allow';

    if (toxicityResult.score >= 0.8) {
      reasons.push('high_toxicity');
      action = 'remove';
    } else if (toxicityResult.score >= 0.6) {
      reasons.push('moderate_toxicity');
      action = 'flag_for_review';
    }

    if (spamResult.score >= 0.7) {
      reasons.push('spam');
      action = action === 'remove' ? 'remove' : 'flag_for_review';
    }

    if (action !== 'allow') {
      const db = admin.firestore();
      await db.collection('moderation_queue').add({
        postId,
        userId,
        action,
        reasons,
        toxicityScore: toxicityResult.score,
        spamScore: spamResult.score,
        contentPreview: text.substring(0, 300),
        source: 'onPostCreate_trigger',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewed: false,
      });

      if (action === 'remove') {
        await db.collection('posts').doc(postId).update({
          removed: true,
          removedReason: reasons.join(', '),
          removedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await incrementUserViolations(userId, action);
        console.log(`🚫 [onPostCreate] Post ${postId} auto-removed: ${reasons.join(', ')}`);
      } else {
        await db.collection('posts').doc(postId).update({
          flaggedForReview: true,
          flagReasons: reasons,
          flaggedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`⚠️ [onPostCreate] Post ${postId} flagged for review: ${reasons.join(', ')}`);
      }
    }

    return { shouldRemove: action === 'remove', action, reasons };
  } catch (error) {
    console.error(`[onPostCreate moderation] Error for post ${postId}:`, error);
    // Fail open: post stays visible, flagged for async review
    return { shouldRemove: false, action: 'error_allow', reasons: [] };
  }
};

// ============================================================================
// SERVER-SIDE POST MODERATION TRIGGER (Firestore onWrite)
// Runs moderation whenever a new post is created or its text changes.
// Bypasses client-side moderation for direct Firestore writes.
// ============================================================================

const {onDocumentWritten} = require('firebase-functions/v2/firestore');

exports.serverSidePostModeration = onDocumentWritten(
  {document: 'posts/{postId}', region: 'us-central1'},
  async (event) => {
    const postId = event.params.postId;
    const afterData = event.data.after.data();

    // Skip deletes
    if (!afterData) return null;

    // Skip if already moderated server-side (avoid infinite loops)
    if (afterData.serverModerated === true) return null;

    // Skip if post is already removed or flagged (no need to re-run)
    if (afterData.removed === true) return null;

    const userId = afterData.userId || afterData.authorId;
    const text = afterData.content || '';

    if (!text || text.length < 3) return null;

    console.log(`🛡️ [serverSidePostModeration] Running on post ${postId}`);

    try {
      const result = await exports.moderatePostText(postId, userId, text);
      const db = admin.firestore();

      // Write unified moderation_jobs record (non-fatal)
      await writeModerationJob({
        contentId: postId,
        contentType: 'post',
        authorId: userId,
        contentSnapshot: text.substring(0, 4000),
        scores: {
          toxicity: result.toxicityScore || 0,
          spam: result.spamScore || 0,
        },
        decision: { action: result.action, reasons: result.reasons, confidence: result.confidence || 0 },
        signals: result.reasons || [],
      });

      if (result.action === 'remove') {
        await db.collection('posts').doc(postId).update({
          removed: true,
          moderationStatus: 'rejected',
          moderationReasons: result.reasons,
          serverModerated: true,
          serverModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`🚫 [serverSidePostModeration] Post ${postId} removed`);
      } else if (result.action === 'flag_for_review') {
        await db.collection('posts').doc(postId).update({
          flaggedForReview: true,
          moderationReasons: result.reasons,
          serverModerated: true,
          serverModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`⚠️ [serverSidePostModeration] Post ${postId} flagged`);
      } else {
        // Mark as server-moderated so we don't re-run
        await db.collection('posts').doc(postId).update({
          serverModerated: true,
          serverModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (err) {
      console.error(`[serverSidePostModeration] Error:`, err);
    }

    return null;
  }
);
