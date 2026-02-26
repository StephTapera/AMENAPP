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

// Initialize Vertex AI (Google Cloud AI Platform)
const {LanguageServiceClient} = require('@google-cloud/language');
const languageClient = new LanguageServiceClient();

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

    // 5. Log moderation event
    await logModerationEvent({
      userId,
      contentType,
      contentText: contentText.substring(0, 500),  // Truncate for storage
      decision,
      scores,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

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
    // Default to allow on error (fail open, log for review)
    await logModerationError(userId, contentType, error);
    return {
      decision: 'allow',
      confidence: 0,
      reasons: ['Error in moderation - defaulting to allow'],
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
    const [result] = await languageClient.moderateText({document});
    
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
