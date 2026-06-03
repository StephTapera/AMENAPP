'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const VALID_REASONS = [
    'crisisMishandled',
    'harassment',
    'fabricatedScripture',
    'harmful',
    'theologicallyMisleading',
    'other',
];

exports.reportUnsafeAIResponse = onCall(
    {
        enforceAppCheck: true,
        region: 'us-central1',
    },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError('unauthenticated', 'Sign in required.');
        }

        const { messageId, conversationId, reason, details, surface } = request.data;

        if (!reason || !VALID_REASONS.includes(reason)) {
            throw new HttpsError('invalid-argument', `reason must be one of: ${VALID_REASONS.join(', ')}`);
        }

        const safeDetails = typeof details === 'string' ? details.slice(0, 500) : '';
        const safeMessageId = typeof messageId === 'string' ? messageId.slice(0, 128) : '';
        const safeConversationId = typeof conversationId === 'string' ? conversationId.slice(0, 128) : '';
        const safeSurface = typeof surface === 'string' ? surface.slice(0, 64) : 'unknown';

        const ref = await admin.firestore().collection('aiReports').add({
            userId: request.auth.uid,
            messageId: safeMessageId,
            conversationId: safeConversationId,
            reason,
            details: safeDetails,
            surface: safeSurface,
            reportedAt: admin.firestore.Timestamp.now(),
            status: 'pending_review',
        });

        console.log(`AI report submitted: ${ref.id} reason=${reason} surface=${safeSurface}`);
        return { reportId: ref.id };
    }
);
