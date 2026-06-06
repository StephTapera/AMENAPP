// safeMessagingGateway.js
// Pre-send safety gateway for AMEN messaging
// Analyzes all messages before delivery to prevent harm

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const db = admin.firestore();

// Import shared escalation + decision persistence from the gateway module.
// Lazy-require so module load order doesn't matter at deploy time.
function getGateway() {
    return require('./moderationGateway');
}

// ============================================================================
// SAFETY CLASSIFIERS
// ============================================================================

/**
 * Detects harassment patterns in message content WITH CONTEXTUAL INTELLIGENCE
 */
function detectHarassment(content, history = [], relationshipContext = {}) {
    const patterns = [
        // Direct insults
        /\b(stupid|idiot|loser|worthless|pathetic|trash|garbage)\b/i,

        // Threats
        /\b(hurt|kill|destroy|ruin|get you|harm you)\b/i,

        // Repetition (abusive messages often repeat)
        /(.{10,})\1{2,}/i,

        // All caps aggression
        /^[A-Z\s!?]{20,}$/,

        // Targeted attacks
        /you (are|should|need to|deserve|will|gonna)/i,

        // Profanity patterns
        /\b(fuck|shit|bitch|damn|hell)\b.{0,30}\b(you|your)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.2;
    });

    // ============================================================================
    // CONTEXTUAL INTELLIGENCE: Detect playful vs. harmful intent
    // ============================================================================

    const playfulSignals = [
        /\b(haha|lol|jk|just kidding|joking|lmao|hehe|😂|😭|💀|😅)\b/i,
        /\b(bro|dude|bruh|bestie|friend|sis)\b/i,
        /[!]{2,}|[?!]{2,}/, // Multiple punctuation (playful energy)
        /😊|😄|😁|🤣|😜|😝|😛|🙃/, // Positive emojis
    ];

    const harmfulSignals = [
        /\b(honestly|seriously|actually|literally)\b/i, // Emphasizers suggest seriousness
        /\b(always|never|every time|constantly)\b/i, // Absolutism = genuine criticism
        /\.{3,}/, // Ellipses = passive aggression
        /\b(deserve|should|need to)\b/i, // Directive language
    ];

    const isPlayful = playfulSignals.some(signal => signal.test(content));
    const isHarmful = harmfulSignals.some(signal => signal.test(content));

    // Relationship strength (mutual followers with message history = trusted)
    const isMutualFollower = relationshipContext.mutualFollow || false;
    const messageCount = relationshipContext.totalMessages || 0;
    const recentMessages = history.slice(-10); // Last 10 messages
    const positiveHistory = recentMessages.filter(m =>
        !m.moderationFlags || m.moderationFlags.length === 0
    ).length;

    // ============================================================================
    // CONTEXT-AWARE SCORING ADJUSTMENTS
    // ============================================================================

    // Scenario 1: "haha you're stupid" between friends
    if (isPlayful && isMutualFollower && messageCount > 50 && positiveHistory >= 8) {
        score *= 0.1; // 90% reduction - clearly joking between friends
    }
    // Scenario 2: "you're stupid lol" in early conversation
    else if (isPlayful && messageCount < 10) {
        score *= 0.4; // 60% reduction - probably joking, but not established trust
    }
    // Scenario 3: "you're actually stupid" (no playful signals, has harmful signals)
    else if (isHarmful && !isPlayful) {
        score *= 1.5; // 50% increase - genuine insult
    }
    // Scenario 4: Established relationship without playful signals
    else if (isMutualFollower && messageCount > 100 && positiveHistory >= 9) {
        score *= 0.5; // 50% reduction - benefit of the doubt for long-term friends
    }

    // ============================================================================
    // PATTERN ANALYSIS: Repeated targeting
    // ============================================================================

    // Context: is this continuation of prior harassment?
    const priorHarassment = history.filter(m =>
        m.moderationFlags?.includes('harassment')
    ).length;

    score += Math.min(priorHarassment * 0.15, 0.4); // Escalation detection

    return Math.min(score, 1.0);
}

/**
 * Detects sexual solicitation and inappropriate requests
 */
function detectSexualSolicitation(content, senderAge, recipientAge) {
    const patterns = [
        // Explicit requests
        /\b(send|show|share|post).{0,20}(pic|photo|nude|naked|body|selfie)\b/i,

        // Inappropriate compliments
        /\b(sexy|hot|beautiful|gorgeous).{0,30}(pic|photo|body)\b/i,

        // Grooming language
        /\b(mature|secret|don't tell|our little|between us)\b/i,

        // Payment for content
        /\b(pay|money|cash|venmo).{0,30}(pic|photo|video|meet|date)\b/i,

        // Explicit content
        /\b(sex|sexual|hookup|nudes|dick pic|boobs)\b/i,

        // Dating/hookup requests
        /\b(wanna|want to|let's).{0,20}(hookup|meet up|come over|your place)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.3;
    });

    // Age differential risk (adult → minor)
    if (senderAge >= 18 && recipientAge < 18) {
        score += 0.4;  // Major red flag
    }

    // Young adult → teen (still concerning)
    if (senderAge >= 21 && recipientAge < 16) {
        score += 0.3;
    }

    return Math.min(score, 1.0);
}

/**
 * Detects scam and phishing attempts
 */
function detectScam(content) {
    const patterns = [
        // Financial urgency
        /\b(urgent|act now|limited time|expires|hurry).{0,30}(offer|deal|money|opportunity)\b/i,

        // Too-good-to-be-true
        /\b(free money|easy money|guaranteed|risk-free|no risk|instant cash)\b/i,

        // Credential phishing
        /\b(verify|confirm|update|reset).{0,30}(account|password|payment|card|info)\b/i,

        // External payment requests
        /\b(venmo|cashapp|paypal|zelle|wire transfer|bitcoin|crypto)\b/i,

        // Prize/lottery scams
        /\b(won|winner|prize|lottery|jackpot|claim).{0,30}(money|cash|prize)\b/i,

        // Investment scams
        /\b(invest|investment|returns|profit).{0,30}(guaranteed|risk-free|double|triple)\b/i,

        // Suspicious links
        /\b(bit\.ly|tinyurl|goo\.gl|t\.co)\/\b/i,

        // Click bait
        /\bclick (here|link|this)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.25;
    });

    // Check for suspicious URLs
    const urlPattern = /https?:\/\/[^\s]+/gi;
    const urls = content.match(urlPattern) || [];

    // Multiple URLs is suspicious
    if (urls.length > 2) score += 0.2;

    // Shortened URLs are suspicious
    if (urls.some(url => url.length < 25)) score += 0.2;

    return Math.min(score, 1.0);
}

/**
 * AMEN-SPECIFIC: Detects spiritual abuse and manipulation
 */
function detectSpiritualAbuse(content, senderProfile = {}) {
    const patterns = [
        // Authority manipulation
        /\b(god|lord|spirit|jesus|holy spirit).{0,30}(told|commanded|wants|said|revealed).{0,30}(me|us|you).{0,20}to\b/i,

        // Forced obedience
        /\b(you|must|need to|should|have to).{0,20}(obey|submit|listen|follow|give|tithe)\b/i,

        // Financial exploitation via faith
        /\b(tithe|offering|donation|seed|sow).{0,50}(blessing|favor|miracle|prosperity|breakthrough|harvest)\b/i,
        /\b(god|jesus).{0,30}(bless|reward|provide|multiply).{0,30}(if you|when you|after you).{0,20}(give|donate|sow|tithe)\b/i,

        // Isolation tactics
        /\b(leave|abandon|separate from|cut off).{0,30}(family|friends|church|fellowship|parents)\b/i,
        /\bthey (don't understand|aren't real|against god|not believers|deceived)\b/i,

        // Apocalyptic coercion
        /\b(end times|rapture|judgment|tribulation).{0,30}(act now|urgent|immediately|before|too late)\b/i,

        // Scripture weaponization
        /\b(the bible|scripture|word of god) (says|commands|requires) you (must|should|have to)\b/i,

        // Shaming/condemnation
        /\b(god|jesus).{0,30}(disappointed|angry|punish|curse|condemn|judge).{0,30}(you|your)\b/i,

        // False prophecy/revelation
        /\bgod (told|showed|revealed) me.{0,30}(about you|your future|your sin)\b/i,

        // Cult-like control
        /\b(only I|only we|no one else).{0,30}(can|will|knows|understands).{0,30}(truth|god|way)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.15;
    });

    // Higher risk if sender claims religious authority
    const authorityKeywords = ['pastor', 'elder', 'minister', 'prophet', 'apostle', 'bishop', 'reverend'];
    const bio = (senderProfile.bio || '').toLowerCase();

    if (authorityKeywords.some(kw => bio.includes(kw))) {
        score += 0.2;
    }

    // Check for financial + spiritual combinations (very suspicious)
    const hasMoney = /\b(money|cash|pay|donate|give|offering|tithe)\b/i.test(content);
    const hasSpiritual = /\b(god|jesus|blessing|miracle|faith)\b/i.test(content);

    if (hasMoney && hasSpiritual) {
        score += 0.25;
    }

    return Math.min(score, 1.0);
}

/**
 * Detects grooming patterns (adult → minor)
 */
function detectGrooming(content, messageHistory = [], senderAge, recipientAge) {
    const patterns = [
        // Building trust/secrecy
        /\b(our secret|don't tell|between us|keep this|just us|trust me|special friend)\b/i,

        // Isolation
        /\b(no one understands|they don't care|I'm the only one|I get you)\b/i,

        // Testing boundaries
        /\b(you're (so|very) mature|mature for your age|act older|not like other)\b/i,

        // Progressive requests
        /\bjust one (pic|photo|video|call|favor)\b/i,

        // Gifts/incentives
        /\b(buy you|get you|gift for you).{0,30}(if|when|after)\b/i,

        // Compliments with pressure
        /\b(you're so|you look).{0,20}(beautiful|pretty|hot|sexy).{0,30}(please|come on|just)\b/i,

        // Age references (red flag)
        /\bhow old are you\b/i,
        /\b(age|years old)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.2;
    });

    // Critical age differential
    if (senderAge >= 18 && recipientAge < 16) {
        score += 0.5;  // Immediate red flag
    }

    // Check message progression (escalation detection)
    const messagesFromSender = messageHistory.filter(m => m.role === 'sender');

    if (messagesFromSender.length > 5) {
        // Check if requests are escalating
        const hasEarlierCompliments = messagesFromSender.slice(0, 3).some(m =>
            /\b(nice|cute|pretty|beautiful)\b/i.test(m.content)
        );
        const hasLaterRequests = messagesFromSender.slice(-3).some(m =>
            /\b(send|show|pic|photo|meet)\b/i.test(m.content)
        );

        if (hasEarlierCompliments && hasLaterRequests) {
            score += 0.3;  // Classic grooming escalation
        }
    }

    return Math.min(score, 1.0);
}

/**
 * Detects hate speech and targeted harassment
 */
function detectHateSpeech(content) {
    const patterns = [
        // Racial slurs (use caution with this list)
        /\b(n[i1]gg[ae]r|sp[i1]c|ch[i1]nk|k[i1]ke)\b/i,

        // Religious hate
        /\b(all|every|those).{0,20}(muslims|christians|jews|catholics).{0,30}(are|should|deserve|need to).{0,30}(die|burn|hell)\b/i,

        // LGBTQ+ hate
        /\b(f[a4]gg[o0]t|tr[a4]nny|dyke)\b/i,

        // Violent threats
        /\b(kill|murder|rape|assault|lynch|hang|shoot).{0,30}(all|every|those|them)\b/i,

        // Dehumanization
        /\b(animals|vermin|trash|scum|filth).{0,30}(people|group|race|religion)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.4;
    });

    return Math.min(score, 1.0);
}

/**
 * Detects self-harm and suicide references
 */
function detectSelfHarm(content) {
    const patterns = [
        // Suicidal ideation
        /\b(kill myself|end it all|no reason to live|better off dead|want to die|suicide)\b/i,

        // Self-harm
        /\b(cut myself|hurt myself|self harm|cutting)\b/i,

        // Hopelessness
        /\b(can't go on|give up|no point|worthless|hopeless)\b/i,

        // Methods
        /\b(pills|overdose|jump|hanging|gun)\b.{0,30}\b(kill|die|end)\b/i
    ];

    let score = 0;
    patterns.forEach(pattern => {
        if (pattern.test(content)) score += 0.3;
    });

    return Math.min(score, 1.0);
}

// ============================================================================
// TRUST SCORE SYSTEM
// ============================================================================

/**
 * Calculate user trust score (0.0 - 1.0)
 */
async function getTrustScore(userId) {
    try {
        const userDoc = await db.collection('users').doc(userId).get();

        if (!userDoc.exists) return 0.5; // Default for new users

        const userData = userDoc.data();
        const createdAt = userData.createdAt?.toDate() || new Date();
        const accountAgeMs = Date.now() - createdAt.getTime();
        const accountAgeDays = accountAgeMs / (1000 * 60 * 60 * 24);

        // Get metrics
        const reportCount = userData.reportCount || 0;
        const blockCount = userData.blockCount || 0;
        const messagesSent = userData.messagesSent || 0;
        const messagesAccepted = userData.messagesAccepted || 0;
        const contentViolations = userData.contentViolations || 0;
        const isVerified = userData.emailVerified && userData.phoneVerified;

        // Calculate component scores
        const accountAgeScore = Math.min(accountAgeDays / 30, 1.0); // Max at 30 days
        const verificationScore = isVerified ? 1.0 : 0.5;
        const reportScore = Math.max(0, 1.0 - (reportCount / 10));
        const blockScore = Math.max(0, 1.0 - (blockCount / 10));
        const acceptanceRate = messagesSent > 0 ? messagesAccepted / messagesSent : 0.5;
        const violationScore = Math.max(0, 1.0 - (contentViolations / 10));

        // Weighted trust score
        const trustScore = (
            accountAgeScore * 0.15 +
            verificationScore * 0.10 +
            reportScore * 0.20 +
            blockScore * 0.15 +
            acceptanceRate * 0.15 +
            violationScore * 0.20 +
            0.05 // Base score for everyone
        );

        return Math.max(0.1, Math.min(trustScore, 1.0));

    } catch (error) {
        console.error('Error calculating trust score:', error);
        return 0.5; // Default on error
    }
}

/**
 * Get recipient vulnerability score (higher = more vulnerable)
 */
async function getVulnerabilityScore(userId) {
    try {
        const userDoc = await db.collection('users').doc(userId).get();

        if (!userDoc.exists) return 0.3;

        const userData = userDoc.data();

        // C-17: Use server-computed ageTier for age-based vulnerability.
        // `userData.age` is user-declared and unverified; a predator could set
        // a victim's reported age high to suppress the vulnerability score.
        // `ageTier` is written server-side by the age-assurance pipeline and is
        // not client-writable. Fall back to max vulnerability when tier is absent.
        const ageTier = userData.ageTier || null;
        // Derive age only from verified tier; unknown tier → treat as potential minor.
        const age = ageTier === 'tierD' ? 18          // confirmed adult
                  : ageTier === 'tierC' ? 17          // confirmed 16-17
                  : ageTier === 'tierB' ? 14          // confirmed 13-15
                  : ageTier === 'tierA' ? 10          // confirmed under-13
                  : (userData.age || 13);             // tier absent → assume vulnerable

        let score = 0;

        // Age-based vulnerability
        if (age < 16) score += 0.5;  // Minors very vulnerable
        else if (age < 18) score += 0.3;

        // Account age (new users more vulnerable)
        const createdAt = userData.createdAt?.toDate() || new Date();
        const accountAgeDays = (Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24);
        if (accountAgeDays < 7) score += 0.2;

        // Has been targeted before
        const reportsReceived = userData.reportsReceived || 0;
        if (reportsReceived > 2) score += 0.2;

        return Math.min(score, 1.0);

    } catch (error) {
        console.error('Error calculating vulnerability score:', error);
        return 0.3;
    }
}

// ============================================================================
// CONVERSATION ANALYSIS
// ============================================================================

/**
 * Detect escalation in conversation (sentiment getting worse)
 */
function detectEscalation(messageHistory) {
    if (messageHistory.length < 5) return 0;

    const recent = messageHistory.slice(-10);

    // Check for boundary keywords
    const boundaryKeywords = ['stop', 'no', 'leave me alone', "don't contact", 'blocked', 'reporting'];
    const boundaryViolations = recent.filter(m =>
        m.role === 'recipient' && boundaryKeywords.some(kw => m.content.toLowerCase().includes(kw))
    ).length;

    if (boundaryViolations > 1) return 0.8;  // Clear escalation

    // Check for repeated messages (spam pattern)
    const senderMessages = recent.filter(m => m.role === 'sender');
    const uniqueContent = new Set(senderMessages.map(m => m.content.toLowerCase().trim()));

    if (senderMessages.length > 5 && uniqueContent.size < 3) {
        return 0.6;  // Spam/harassment pattern
    }

    return 0;
}

/**
 * Get conversation risk history
 */
async function getConversationRiskHistory(conversationId) {
    try {
        const snapshot = await db.collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .orderBy('timestamp', 'desc')
            .limit(20)
            .get();

        const messages = snapshot.docs.map(doc => ({
            ...doc.data(),
            id: doc.id
        }));

        return messages;

    } catch (error) {
        console.error('Error getting conversation history:', error);
        return [];
    }
}

// ============================================================================
// MAIN SAFETY GATEWAY
// ============================================================================

/**
 * Main safety gateway - analyzes message before delivery
 */
exports.safeMessageGateway = onCall(async (request) => {
    // Verify authentication
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const senderId = request.auth.uid;
    const { conversationId, messageContent, recipientId, attachments = [] } = request.data;

    try {
        // ================================================================
        // STEP 1: Get context
        // ================================================================

        const [senderDoc, recipientDoc, conversationDoc] = await Promise.all([
            db.collection('users').doc(senderId).get(),
            db.collection('users').doc(recipientId).get(),
            db.collection('conversations').doc(conversationId).get()
        ]);

        const senderData = senderDoc.data() || {};
        const recipientData = recipientDoc.data() || {};
        const conversationData = conversationDoc.data() || {};

        // C-17: Unverified ages must not reduce risk below the adult baseline.
        // `ageTier` is server-computed from birthYear and cannot be self-reported.
        // An attacker who sets their age to 17 in their profile would still have
        // ageTier='tierD' (default adult) if they signed up without providing a
        // confirmed birthYear — so the adult-sender risk boosts in detectGrooming /
        // detectSexualSolicitation will still fire correctly.
        // Rule: treat any sender whose ageTier does NOT confirm minor status as 18+
        // for scoring purposes, so unverified declared ages never suppress adult risk.
        const senderAgeTier = senderData.ageTier || 'tierD';
        const recipientAgeTier = recipientData.ageTier || 'tierD';
        const senderIsVerifiedMinor = (senderAgeTier === 'tierB' || senderAgeTier === 'tierC');
        const recipientIsVerifiedMinor = (recipientAgeTier === 'tierB' || recipientAgeTier === 'tierC');
        // For risk scoring: unverified sender age is floored at 18 (adult).
        // Only allow a sub-18 sender age if the server-computed tier confirms it.
        const senderAge = senderIsVerifiedMinor ? (senderData.age || 17) : Math.max(senderData.age || 18, 18);
        // Recipient age uses declared value regardless — being mis-classified as older only
        // reduces the grooming bonus (conservative), but the COPPA gate below uses ageTier.
        const recipientAge = recipientData.age || 18;

        // ================================================================
        // STEP 2: Quick reject gates
        // ================================================================

        // Check if sender is banned
        if (senderData.isBanned) {
            return {
                decision: 'blocked',
                reason: 'sender_banned',
                userFacingReason: 'Your account has been restricted from sending messages.'
            };
        }

        // Check if conversation is blocked
        const blockedBy = conversationData.blockedBy || [];
        if (blockedBy.includes(recipientId)) {
            return {
                decision: 'blocked',
                reason: 'conversation_blocked',
                userFacingReason: 'This conversation is no longer available.'
            };
        }

        // ================================================================
        // C-5 COPPA GATE: Block adult → minor DMs (server-enforced)
        // Uses server-computed ageTier (not user-declared age) so self-reporting
        // cannot bypass the guard. tierA = under 13, tierB = 13-15, tierC = 16-17.
        // ================================================================
        {
            const senderTierForCoppa = senderData.ageTier || 'tierD';
            const recipientTierForCoppa = recipientData.ageTier || 'tierD';

            // Derive ages from verified server tier for COPPA math
            const currentYear = new Date().getFullYear();
            const senderAgeForCoppa = senderData.birthYear
                ? (currentYear - senderData.birthYear)
                : (senderTierForCoppa === 'tierD' ? 18 : senderTierForCoppa === 'tierC' ? 17 : 15);
            const recipientAgeForCoppa = recipientData.birthYear
                ? (currentYear - recipientData.birthYear)
                : (recipientTierForCoppa === 'tierA' ? 10 : recipientTierForCoppa === 'tierB' ? 14
                  : recipientTierForCoppa === 'tierC' ? 17 : 18);

            // Hard block: adult (18+) messaging a user confirmed under-13
            if (recipientTierForCoppa === 'tierA' && senderAgeForCoppa >= 18) {
                await db.collection('moderationIncidents').add({
                    type: 'coppa_dm_block',
                    senderId: senderId,
                    recipientId: recipientId,
                    conversationId: conversationId,
                    senderAge: senderAgeForCoppa,
                    recipientAge: recipientAgeForCoppa,
                    eventType: 'adult_to_under13_dm_blocked',
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
                return {
                    decision: 'blocked',
                    reason: 'coppa_minor_protection',
                    userFacingReason: 'You cannot send direct messages to users under 13.'
                };
            }

            // Flag for review: adult 21+ contacting a server-confirmed minor (13-17)
            if ((recipientTierForCoppa === 'tierB' || recipientTierForCoppa === 'tierC')
                && senderAgeForCoppa >= 21) {
                await db.collection('messageSafetyEvents').add({
                    senderUID: senderId,
                    recipientUID: recipientId,
                    senderAge: senderAgeForCoppa,
                    recipientAge: recipientAgeForCoppa,
                    senderAgeTier: senderTierForCoppa,
                    recipientAgeTier: recipientTierForCoppa,
                    eventType: 'adult_minor_contact_attempt',
                    requiresReview: true,
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
                // Message still flows but is flagged for human review
            }
        }

        // ================================================================
        // STEP 3: Get trust and vulnerability scores
        // ================================================================

        const [senderTrust, recipientVulnerable] = await Promise.all([
            getTrustScore(senderId),
            getVulnerabilityScore(recipientId)
        ]);

        // Very low trust senders blocked immediately
        if (senderTrust < 0.1) {
            await db.collection('users').doc(senderId).update({
                contentViolations: admin.firestore.FieldValue.increment(1)
            });

            return {
                decision: 'blocked',
                reason: 'trust_too_low',
                userFacingReason: 'Your account trust score is too low to send messages.'
            };
        }

        // ================================================================
        // STEP 4: Build relationship context for contextual intelligence
        // ================================================================

        const messageHistory = await getConversationRiskHistory(conversationId);

        // Check if users mutually follow each other
        const [senderFollowsRecipient, recipientFollowsSender] = await Promise.all([
            db.collection('users').doc(senderId)
                .collection('following').doc(recipientId).get(),
            db.collection('users').doc(recipientId)
                .collection('following').doc(senderId).get()
        ]);

        const mutualFollow = senderFollowsRecipient.exists && recipientFollowsSender.exists;

        // Count total messages in conversation
        const messagesSnapshot = await db.collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .count()
            .get();

        const relationshipContext = {
            mutualFollow: mutualFollow,
            totalMessages: messagesSnapshot.data().count,
            conversationAge: conversationData.createdAt ?
                (Date.now() - conversationData.createdAt.toMillis()) / (1000 * 60 * 60 * 24) : 0 // days
        };

        // ================================================================
        // STEP 5: Run safety classifiers with contextual intelligence
        // ================================================================

        const [
            harassmentScore,
            sexualScore,
            scamScore,
            spiritualAbuseScore,
            groomingScore,
            hateSpeechScore,
            selfHarmScore,
            escalationScore
        ] = await Promise.all([
            Promise.resolve(detectHarassment(messageContent, messageHistory, relationshipContext)),
            Promise.resolve(detectSexualSolicitation(messageContent, senderAge, recipientAge)),
            Promise.resolve(detectScam(messageContent)),
            Promise.resolve(detectSpiritualAbuse(messageContent, senderData)),
            Promise.resolve(detectGrooming(messageContent, messageHistory, senderAge, recipientAge)),
            Promise.resolve(detectHateSpeech(messageContent)),
            Promise.resolve(detectSelfHarm(messageContent)),
            Promise.resolve(detectEscalation(messageHistory))
        ]);

        // Find highest risk category
        const scores = {
            harassment: harassmentScore,
            sexual: sexualScore,
            scam: scamScore,
            spiritualAbuse: spiritualAbuseScore,
            grooming: groomingScore,
            hateSpeech: hateSpeechScore,
            selfHarm: selfHarmScore,
            escalation: escalationScore
        };

        const maxScore = Math.max(...Object.values(scores));
        const primaryThreat = Object.keys(scores).find(key => scores[key] === maxScore);

        // ================================================================
        // STEP 5: Calculate final risk score
        // ================================================================

        const finalRisk = (
            maxScore * 0.5 +                    // Classifier score (50%)
            (1 - senderTrust) * 0.2 +          // Sender trust inverse (20%)
            recipientVulnerable * 0.2 +        // Recipient vulnerability (20%)
            escalationScore * 0.1              // Conversation escalation (10%)
        );

        // ================================================================
        // STEP 6: Make decision
        // ================================================================

        // CRITICAL RISK - Block immediately
        if (finalRisk > 0.9 || hateSpeechScore > 0.7 || groomingScore > 0.7) {
            // Log the incident
            await db.collection('moderationIncidents').add({
                type: 'message_blocked',
                senderId: senderId,
                recipientId: recipientId,
                conversationId: conversationId,
                content: messageContent,
                riskScore: finalRisk,
                primaryThreat: primaryThreat,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            // Decrement trust score
            await db.collection('users').doc(senderId).update({
                trustScore: Math.max(0, senderTrust - 0.3),
                contentViolations: admin.firestore.FieldValue.increment(1)
            });

            // Persist to canonical moderationDecisions/
            const { persistDecision: pd1 } = getGateway();
            const blockedDecisionId = await pd1({
                uid: senderId,
                contentType: 'message',
                contextId: conversationId,
                decision: 'block',
                reason: `Critical risk: ${primaryThreat}`,
                detectedCategories: [primaryThreat],
                crisisEscalated: false,
                contentLength: (messageContent || '').length,
                source: 'safeMessageGateway_critical',
            }).catch(() => 'unknown');

            return {
                decision: 'blocked',
                reason: primaryThreat,
                riskScore: finalRisk,
                decisionId: blockedDecisionId,
                userFacingReason: getUserFacingExplanation(primaryThreat, 'blocked')
            };
        }

        // HIGH RISK - Hold for human review
        if (finalRisk > 0.7 || (recipientVulnerable > 0.5 && finalRisk > 0.5)) {
            // Add to moderation queue
            await db.collection('moderationQueue').add({
                type: 'message_review',
                senderId: senderId,
                recipientId: recipientId,
                conversationId: conversationId,
                content: messageContent,
                riskScore: finalRisk,
                primaryThreat: primaryThreat,
                senderTrust: senderTrust,
                recipientVulnerable: recipientVulnerable,
                priority: recipientVulnerable > 0.5 ? 'high' : 'medium',
                status: 'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Persist to canonical moderationDecisions/
            const { persistDecision: pd2 } = getGateway();
            const heldDecisionId = await pd2({
                uid: senderId,
                contentType: 'message',
                contextId: conversationId,
                decision: 'review',
                reason: `High risk: ${primaryThreat}`,
                detectedCategories: [primaryThreat],
                crisisEscalated: false,
                contentLength: (messageContent || '').length,
                source: 'safeMessageGateway_high',
            }).catch(() => 'unknown');

            return {
                decision: 'held',
                reason: primaryThreat,
                riskScore: finalRisk,
                estimatedReviewTime: '2-24 hours',
                decisionId: heldDecisionId,
                userFacingReason: getUserFacingExplanation(primaryThreat, 'held')
            };
        }

        // MEDIUM RISK - Warn recipient
        if (finalRisk > 0.5) {
            return {
                decision: 'warn',
                reason: primaryThreat,
                riskScore: finalRisk,
                warningType: 'caution',
                messageId: null // Will be set after delivery
            };
        }

        // ================================================================
        // SELF-HARM DETECTION — crisis escalation path (never silent block)
        // ================================================================
        if (selfHarmScore > 0.6) {
            console.warn(`[safeMessageGateway] SELF-HARM detected senderId=${senderId} score=${selfHarmScore}`);

            // 1. Persist a moderation decision record
            const { persistDecision, escalateSelfHarm } = getGateway();
            const decisionId = await persistDecision({
                uid: senderId,
                contentType: 'message',
                contextId: conversationId,
                decision: 'review',
                reason: 'Self-harm language detected in message',
                detectedCategories: ['self_harm'],
                crisisEscalated: true,
                contentLength: (messageContent || '').length,
                source: 'safeMessageGateway',
            }).catch((err) => {
                console.error('[safeMessageGateway] persistDecision failed:', err.message);
                return 'unknown';
            });

            // 2. Write crisisEscalations/{uid}/{timestamp} + moderatorAlerts
            await escalateSelfHarm(
                senderId,
                messageContent,
                'message',
                conversationId,
                decisionId
            ).catch((err) => {
                console.error('[safeMessageGateway] escalateSelfHarm failed:', err.message);
            });

            // 3. Return crisis resources to the client (not a silent block)
            return {
                decision: 'deliver_with_resources',
                reason: 'self_harm_detected',
                riskScore: selfHarmScore,
                offerCrisisResources: true,
                crisisEscalated: true,
                decisionId,
                crisisResources: [
                    { name: '988 Suicide & Crisis Lifeline', number: '988', url: 'https://988lifeline.org' },
                    { name: 'Crisis Text Line', instruction: 'Text HOME to 741741', url: 'https://www.crisistextline.org' },
                    { name: 'SAMHSA National Helpline', number: '1-800-662-4357', url: 'https://www.samhsa.gov/find-help/national-helpline' },
                ],
            };
        }

        // ================================================================
        // Persist final moderation decision for all non-crisis outcomes
        // ================================================================
        const finalDecision = finalRisk <= 0.5 ? 'allow' : (finalRisk <= 0.7 ? 'warn' : 'review');
        const { persistDecision: persist } = getGateway();
        const decisionId = await persist({
            uid: senderId,
            contentType: 'message',
            contextId: conversationId,
            decision: finalDecision,
            reason: primaryThreat !== 'safe' ? primaryThreat : null,
            detectedCategories: primaryThreat !== 'safe' ? [primaryThreat] : [],
            crisisEscalated: false,
            contentLength: (messageContent || '').length,
            source: 'safeMessageGateway',
        }).catch((err) => {
            console.error('[safeMessageGateway] persistDecision failed:', err.message);
            return 'unknown';
        });

        // LOW RISK - Deliver normally
        return {
            decision: 'safe',
            riskScore: finalRisk,
            reason: 'safe',
            decisionId,
        };

    } catch (error) {
        console.error('Safety gateway error:', error);

        // On error, default to hold for review (safe choice)
        return {
            decision: 'held',
            reason: 'system_error',
            userFacingReason: 'Your message is being reviewed. This usually takes a few minutes.'
        };
    }
});

/**
 * Get user-facing explanation for moderation decision
 */
function getUserFacingExplanation(category, action) {
    const explanations = {
        harassment: {
            blocked: 'This message may contain language that could be hurtful or harmful. We\'re committed to fostering respect and kindness in all conversations.',
            held: 'This message may contain language that needs review. We care about healthy communication and want to ensure all messages align with our community standards.'
        },
        sexual: {
            blocked: 'This message may contain inappropriate requests. We\'re committed to protecting all users, especially minors, from unwanted advances.',
            held: 'This message contains content that needs review to ensure it meets our community standards for appropriate communication.'
        },
        scam: {
            blocked: 'This message shows signs of a potential scam. We\'re protecting you and others from financial harm.',
            held: 'This message is being reviewed for potential scam patterns. We take user safety seriously.'
        },
        spiritualAbuse: {
            blocked: 'This message may use faith language in a manipulative way. God\'s truth should never be weaponized to control or harm others.',
            held: 'This message is being reviewed for potential spiritual manipulation. We believe faith should build up, not tear down.'
        },
        grooming: {
            blocked: 'This message shows patterns that could indicate an attempt to build inappropriate trust. User safety is our top priority.',
            held: 'This message is being reviewed for patterns that may pose a risk. We\'re committed to protecting all users, especially minors.'
        },
        hateSpeech: {
            blocked: 'This message contains language that targets or demeans others. We do not tolerate hate speech on AMEN.',
            held: 'This message is being reviewed for potentially harmful language. We\'re committed to a community of love and respect.'
        },
        escalation: {
            held: 'This conversation is being reviewed due to concerning patterns. We want to ensure all users feel safe.'
        }
    };

    return explanations[category]?.[action] || 'Your message is being reviewed to ensure it meets our community standards.';
}

// Export for testing
module.exports = {
    detectHarassment,
    detectSexualSolicitation,
    detectScam,
    detectSpiritualAbuse,
    detectGrooming,
    detectHateSpeech,
    detectSelfHarm,
    getTrustScore,
    getVulnerabilityScore
};
