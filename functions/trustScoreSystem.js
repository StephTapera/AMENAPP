// trustScoreSystem.js
// Trust score calculation and reputation management for AMEN
// Tracks user behavior to inform safety decisions

const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const db = admin.firestore();

/**
 * Update trust score when user receives a report
 */
exports.onUserReported = onDocumentCreated('reports/{reportId}', async (event) => {
    const reportData = event.data.data();
    const reportedUserId = reportData.reportedUserId;

    if (!reportedUserId) return;

    try {
        const userRef = db.collection('users').doc(reportedUserId);
        const userDoc = await userRef.get();

        if (!userDoc.exists) return;

        const userData = userDoc.data();
        const currentReportCount = userData.reportCount || 0;
        const currentTrustScore = userData.trustScore || 0.8;

        // Decrement trust score based on report severity
        let trustDecrement = 0.05; // Default

        if (reportData.reason === 'harassment') trustDecrement = 0.1;
        if (reportData.reason === 'sexual_content') trustDecrement = 0.15;
        if (reportData.reason === 'hate_speech') trustDecrement = 0.2;
        if (reportData.reason === 'grooming') trustDecrement = 0.25;
        if (reportData.reason === 'scam') trustDecrement = 0.1;
        if (reportData.reason === 'spiritual_abuse') trustDecrement = 0.15;

        const newTrustScore = Math.max(0, currentTrustScore - trustDecrement);

        // Update user document
        await userRef.update({
            reportCount: currentReportCount + 1,
            trustScore: newTrustScore,
            lastReportedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // If trust score drops below threshold, restrict account
        if (newTrustScore < 0.2) {
            await userRef.update({
                accountRestricted: true,
                restrictionReason: 'low_trust_score',
                restrictedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Notify moderation team
            await db.collection('moderationAlerts').add({
                type: 'low_trust_user',
                userId: reportedUserId,
                trustScore: newTrustScore,
                reportCount: currentReportCount + 1,
                priority: 'high',
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }

    } catch (error) {
        console.error('Error updating trust score on report:', error);
    }
});

/**
 * Update trust score when user is blocked
 */
exports.onUserBlocked = onDocumentCreated('users/{userId}/blockedUsers/{blockedUserId}', async (event) => {
    const blockedUserId = event.params.blockedUserId;

    try {
        const userRef = db.collection('users').doc(blockedUserId);
        const userDoc = await userRef.get();

        if (!userDoc.exists) return;

        const userData = userDoc.data();
        const currentBlockCount = userData.blockCount || 0;
        const currentTrustScore = userData.trustScore || 0.8;

        // Decrement trust score
        const newTrustScore = Math.max(0, currentTrustScore - 0.03);

        await userRef.update({
            blockCount: currentBlockCount + 1,
            trustScore: newTrustScore,
            lastBlockedAt: admin.firestore.FieldValue.serverTimestamp()
        });

    } catch (error) {
        console.error('Error updating trust score on block:', error);
    }
});

/**
 * Update trust score when message request is accepted
 */
exports.onMessageRequestAccepted = onDocumentUpdated('conversations/{conversationId}', async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Check if state changed from request to accepted
    if (before.state === 'request' && after.state === 'accepted') {
        const requestedBy = after.requestedBy;

        if (!requestedBy) return;

        try {
            const userRef = db.collection('users').doc(requestedBy);
            const userDoc = await userRef.get();

            if (!userDoc.exists) return;

            const userData = userDoc.data();
            const messagesSent = userData.messagesSent || 0;
            const messagesAccepted = (userData.messagesAccepted || 0) + 1;

            // Increment acceptance count
            await userRef.update({
                messagesAccepted: messagesAccepted,
                acceptanceRate: messagesAccepted / Math.max(messagesSent, 1)
            });

            // If acceptance rate is good, slowly improve trust score
            if (messagesAccepted > 10 && (messagesAccepted / messagesSent) > 0.7) {
                const currentTrustScore = userData.trustScore || 0.8;
                const newTrustScore = Math.min(1.0, currentTrustScore + 0.01);

                await userRef.update({
                    trustScore: newTrustScore
                });
            }

        } catch (error) {
            console.error('Error updating trust score on request acceptance:', error);
        }
    }
});

/**
 * Update trust score when message request is declined
 */
exports.onMessageRequestDeclined = onDocumentUpdated('conversations/{conversationId}', async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Check if state changed from request to declined
    if (before.state === 'request' && after.state === 'declined') {
        const requestedBy = after.requestedBy;

        if (!requestedBy) return;

        try {
            const userRef = db.collection('users').doc(requestedBy);
            const userDoc = await userRef.get();

            if (!userDoc.exists) return;

            const userData = userDoc.data();
            const messagesSent = userData.messagesSent || 0;
            const messagesDeclined = (userData.messagesDeclined || 0) + 1;

            // Increment decline count
            await userRef.update({
                messagesDeclined: messagesDeclined,
                declineRate: messagesDeclined / Math.max(messagesSent, 1)
            });

            // If decline rate is high, lower trust score
            if (messagesDeclined > 5 && (messagesDeclined / messagesSent) > 0.5) {
                const currentTrustScore = userData.trustScore || 0.8;
                const newTrustScore = Math.max(0.1, currentTrustScore - 0.05);

                await userRef.update({
                    trustScore: newTrustScore
                });
            }

        } catch (error) {
            console.error('Error updating trust score on request decline:', error);
        }
    }
});

/**
 * Calculate and update trust score daily for all users
 */
exports.recalculateTrustScores = onSchedule('every 24 hours', async (event) => {
    try {
        // Process in batches
        const batchSize = 500;
        let lastDoc = null;

        while (true) {
            let query = db.collection('users')
                .orderBy('createdAt')
                .limit(batchSize);

            if (lastDoc) {
                query = query.startAfter(lastDoc);
            }

            const snapshot = await query.get();

            if (snapshot.empty) break;

            const batch = db.batch();

            for (const doc of snapshot.docs) {
                const userData = doc.data();
                const trustScore = calculateComprehensiveTrustScore(userData);

                batch.update(doc.ref, { trustScore: trustScore });
            }

            await batch.commit();

            lastDoc = snapshot.docs[snapshot.docs.length - 1];

            if (snapshot.size < batchSize) break;
        }

        console.log('Trust scores recalculated successfully');

    } catch (error) {
        console.error('Error recalculating trust scores:', error);
    }
});

/**
 * Calculate comprehensive trust score
 */
function calculateComprehensiveTrustScore(userData) {
    const createdAt = userData.createdAt?.toDate() || new Date();
    const accountAgeMs = Date.now() - createdAt.getTime();
    const accountAgeDays = accountAgeMs / (1000 * 60 * 60 * 24);

    // Component scores
    const accountAgeScore = Math.min(accountAgeDays / 30, 1.0);
    const verificationScore = (userData.emailVerified && userData.phoneVerified) ? 1.0 : 0.5;

    const reportCount = userData.reportCount || 0;
    const reportScore = Math.max(0, 1.0 - (reportCount / 10));

    const blockCount = userData.blockCount || 0;
    const blockScore = Math.max(0, 1.0 - (blockCount / 10));

    const messagesSent = userData.messagesSent || 0;
    const messagesAccepted = userData.messagesAccepted || 0;
    const acceptanceRate = messagesSent > 0 ? messagesAccepted / messagesSent : 0.5;

    const contentViolations = userData.contentViolations || 0;
    const violationScore = Math.max(0, 1.0 - (contentViolations / 10));

    // Activity consistency (detect bot-like behavior)
    const messagesPerDay = messagesSent / Math.max(accountAgeDays, 1);
    let activityScore = 1.0;
    if (messagesPerDay > 100) activityScore = 0.3; // Likely spam bot
    else if (messagesPerDay > 50) activityScore = 0.6;

    // Weighted calculation
    const trustScore = (
        accountAgeScore * 0.15 +
        verificationScore * 0.10 +
        reportScore * 0.20 +
        blockScore * 0.15 +
        acceptanceRate * 0.15 +
        violationScore * 0.20 +
        activityScore * 0.05
    );

    return Math.max(0.1, Math.min(trustScore, 1.0));
}

/**
 * Initialize trust score for new users
 */
exports.initializeTrustScore = onDocumentCreated('users/{userId}', async (event) => {
    try {
        await event.data.ref.update({
            trustScore: 0.5, // New users start at neutral
            reportCount: 0,
            blockCount: 0,
            messagesSent: 0,
            messagesAccepted: 0,
            messagesDeclined: 0,
            contentViolations: 0,
            acceptanceRate: 0.5,
            declineRate: 0
        });
    } catch (error) {
        console.error('Error initializing trust score:', error);
    }
});
