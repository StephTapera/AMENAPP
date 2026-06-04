'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// These must match AIUnsafeResponseReporter.Reason rawValues in AIUnsafeResponseReporter.swift.
const VALID_REASONS = [
    'unsafe_advice',
    'false_doctrine',
    'claims_divine_authority',
    'crisis_mishandled',
    'harassment_or_hate',
    'private_info_leak',
    'fabricated_scripture',
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
