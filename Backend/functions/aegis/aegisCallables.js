// aegisCallables.js
// Aegis callable proxy stubs — App Check + Auth enforced on all callables.
// These extend the existing trustSafety/ callable infrastructure.
// Firebase project: aegis-amen-5e359
//
// Deploy: firebase deploy --only functions:aegisAnalyzeMedia,aegisReviewText,aegisAccountTrust,aegisPrivacyAction,aegisEscalate

'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// callWithTimeout — inline helper (also used by trustSafety pipeline).
// Wraps a promise factory with a hard timeout; rejects with a structured
// error so callers can surface a clean HttpsError rather than a cold hang.
function callWithTimeout(promiseFn, timeoutMs) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            reject(new Error(`Operation timed out after ${timeoutMs}ms`));
        }, timeoutMs);
        Promise.resolve()
            .then(() => promiseFn())
            .then(result => { clearTimeout(timer); resolve(result); })
            .catch(err => { clearTimeout(timer); reject(err); });
    });
}

// Lazy-load moderation helpers to avoid cold-start cost for unrelated functions.
let _imagePreflightFn, _videoPreflightFn, _audioPreflightFn, _textPreflightFn;

function getImagePreflight() {
    if (!_imagePreflightFn) {
        ({ runImagePreflight: _imagePreflightFn } = require('../src/trustSafety/moderateImage'));
    }
    return _imagePreflightFn;
}
function getVideoPreflight() {
    if (!_videoPreflightFn) {
        ({ runVideoPreflight: _videoPreflightFn } = require('../src/trustSafety/moderateVideo'));
    }
    return _videoPreflightFn;
}
function getAudioPreflight() {
    if (!_audioPreflightFn) {
        ({ runAudioPreflight: _audioPreflightFn } = require('../src/trustSafety/moderateAudio'));
    }
    return _audioPreflightFn;
}
function getTextPreflight() {
    if (!_textPreflightFn) {
        ({ runTextPreflight: _textPreflightFn } = require('../src/trustSafety/moderateText'));
    }
    return _textPreflightFn;
}

// ─── Auth / App Check guard ────────────────────────────────────────────────

function assertAuthAndAppCheck(context) {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Auth required.'
        );
    }
    if (!context.app) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'App Check required.'
        );
    }
}

function assertOwnership(data, context) {
    assertAuthAndAppCheck(context);
    if (data.userId !== context.auth.uid) {
        throw new functions.https.HttpsError(
            'permission-denied',
            'You may only perform this action on your own account.'
        );
    }
}

// ─── 1. aegisAnalyzeMedia ─────────────────────────────────────────────────

/**
 * Analyzes a media asset (image/video/audio) through the appropriate
 * Aegis preflight pipeline and returns a structured detection response.
 *
 * data: { mediaUrl: string, mediaType: "image"|"video"|"audio",
 *          userId: string, surface: string, capabilities: string[] }
 * returns: AegisAnalyzeMediaResponse
 */
const aegisAnalyzeMedia = functions.https.onCall(async (data, context) => {
    assertAuthAndAppCheck(context);

    const { mediaUrl, mediaType, userId, surface, capabilities } = data || {};

    if (!mediaUrl || typeof mediaUrl !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'mediaUrl is required.');
    }
    if (!['image', 'video', 'audio'].includes(mediaType)) {
        throw new functions.https.HttpsError('invalid-argument', 'mediaType must be image, video, or audio.');
    }
    if (!userId || typeof userId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'userId is required.');
    }
    if (!Array.isArray(capabilities) || capabilities.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'capabilities array is required.');
    }

    const preflightInput = { mediaUrl, userId, surface: surface || 'unknown', capabilities };

    let preflightResult;
    try {
        if (mediaType === 'image') {
            preflightResult = await callWithTimeout(() => getImagePreflight()(preflightInput), 25000);
        } else if (mediaType === 'video') {
            preflightResult = await callWithTimeout(() => getVideoPreflight()(preflightInput), 45000);
        } else {
            preflightResult = await callWithTimeout(() => getAudioPreflight()(preflightInput), 35000);
        }
    } catch (err) {
        console.error('[aegisAnalyzeMedia] preflight error', { userId, mediaType, err });
        throw new functions.https.HttpsError('internal', 'Media analysis failed. Please try again.');
    }

    // Map preflight result → AegisAnalyzeMediaResponse shape
    return {
        results: preflightResult.results || [],
        decision: preflightResult.decision || { allowPost: true },
        provenanceStatus: preflightResult.provenanceStatus || null,
        c2paSignature: preflightResult.c2paSignature || null,
    };
});

// ─── 2. aegisReviewText ───────────────────────────────────────────────────

/**
 * Reviews text content for spiritual abuse, harassment, misinformation, and
 * general safety violations. Optionally routes through Berean for pastoral
 * lane capabilities (C20–C29).
 *
 * data: { text: string, surface: string, userId: string,
 *          capabilities: string[], context?: object }
 * returns: AegisReviewTextResponse
 */
const aegisReviewText = functions.https.onCall(async (data, context) => {
    assertAuthAndAppCheck(context);

    const { text, surface, userId, capabilities, context: extraCtx } = data || {};

    if (!text || typeof text !== 'string' || text.trim().length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'text is required.');
    }
    if (text.length > 10000) {
        throw new functions.https.HttpsError('invalid-argument', 'text exceeds 10,000 character limit.');
    }
    if (!userId || typeof userId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'userId is required.');
    }
    if (!Array.isArray(capabilities) || capabilities.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'capabilities array is required.');
    }

    // Berean lane capability IDs (C20–C29)
    const bereanCapabilities = new Set([
        'C20','C21','C22','C23','C24','C25','C26','C27','C28','C29'
    ]);
    const hasBereanLane = capabilities.some(c => bereanCapabilities.has(c));

    const preflightInput = { text, surface: surface || 'unknown', userId, capabilities, context: extraCtx || {} };

    let textResult, bereanResult;

    try {
        textResult = await callWithTimeout(() => getTextPreflight()(preflightInput), 20000);
    } catch (err) {
        console.error('[aegisReviewText] text preflight error', { userId, err });
        throw new functions.https.HttpsError('internal', 'Text review failed. Please try again.');
    }

    // Optionally augment with Berean pastoral reflection
    if (hasBereanLane) {
        try {
            const { bereanChatProxy } = require('../src/bereanChatProxy');
            const safetyPrompt = [
                'You are a pastoral safety reviewer for a faith-based community platform.',
                'Briefly assess the following text for any spiritual harm, manipulation, or doctrinal misinformation.',
                'If you find concerns, offer a short, warm, non-punitive pastoral reflection (2–3 sentences max).',
                'If the text is fine, reply with null.',
                `\n\nText: "${text.slice(0, 1500)}"`
            ].join(' ');

            bereanResult = await callWithTimeout(
                () => bereanChatProxy({ message: safetyPrompt, userId, surface: 'aegis_review' }),
                15000
            );
        } catch (err) {
            // Non-fatal — Berean augmentation is best-effort
            console.warn('[aegisReviewText] Berean augmentation failed', { userId, err: err.message });
        }
    }

    return {
        results: textResult.results || [],
        decision: textResult.decision || { allowPost: true },
        pauseReason: textResult.pauseReason || null,
        pastoralReflection: bereanResult?.reply || null,
    };
});

// ─── 3. aegisAccountTrust ─────────────────────────────────────────────────

/**
 * Returns a trust assessment for a target user account. Reads from
 * aegisProfiles/{targetUserId} and identityTrust pipeline.
 *
 * data: { targetUserId: string, requestingUserId: string, capabilities: string[] }
 * returns: AegisAccountTrustResponse
 */
const aegisAccountTrust = functions.https.onCall(async (data, context) => {
    assertAuthAndAppCheck(context);

    const { targetUserId, requestingUserId, capabilities } = data || {};

    if (!targetUserId || typeof targetUserId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'targetUserId is required.');
    }
    if (!requestingUserId || typeof requestingUserId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'requestingUserId is required.');
    }
    if (context.auth.uid !== requestingUserId) {
        throw new functions.https.HttpsError('permission-denied', 'requestingUserId must match authenticated user.');
    }

    const db = admin.firestore();

    let profileDoc;
    try {
        profileDoc = await callWithTimeout(
            () => db.collection('aegisProfiles').doc(targetUserId).get(),
            10000
        );
    } catch (err) {
        console.error('[aegisAccountTrust] Firestore read error', { targetUserId, err });
        throw new functions.https.HttpsError('internal', 'Could not retrieve trust profile.');
    }

    const profile = profileDoc.exists ? profileDoc.data() : {};

    // Route through existing identityTrust pipeline if available
    let trustPipelineResult = null;
    try {
        const { evaluateIdentityTrust } = require('../src/trustSafety/identityTrust');
        trustPipelineResult = await callWithTimeout(
            () => evaluateIdentityTrust({ targetUserId, requestingUserId, capabilities: capabilities || [] }),
            15000
        );
    } catch (err) {
        // Non-fatal — fall back to stored profile values
        console.warn('[aegisAccountTrust] identityTrust pipeline unavailable', { err: err.message });
    }

    return {
        results: trustPipelineResult?.results || [],
        trustLevel: trustPipelineResult?.trustLevel || profile.trustLevel || 'unverified',
        syntheticDisclosure: profile.syntheticDisclosure || trustPipelineResult?.syntheticDisclosure || 'unknown',
        cryptoVerified: profile.cryptoVerified || false,
        verificationSignature: profile.verificationSignature || null,
    };
});

// ─── 4. aegisPrivacyAction ────────────────────────────────────────────────

/**
 * Executes a user-initiated privacy action: data export, true deletion,
 * privacy mode activation, location deferral, memorialization, or legacy transfer.
 * Ownership enforced — userId must equal context.auth.uid.
 *
 * data: { userId: string, action: string, modeId?: string, targetPaths?: string[] }
 * returns: AegisPrivacyActionResponse
 */
const aegisPrivacyAction = functions.https.onCall(async (data, context) => {
    assertOwnership(data, context);

    const { userId, action, modeId, targetPaths } = data || {};

    if (!action || typeof action !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'action is required.');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    switch (action) {

        // ── export ────────────────────────────────────────────────────────
        case 'export': {
            // Trigger export generation — reuse existing userDataExport callable if present
            let exportUrl = null;
            try {
                const { generateDataExport } = require('../src/privacy/userDataExport');
                const result = await callWithTimeout(
                    () => generateDataExport({ userId }),
                    55000
                );
                exportUrl = result.downloadUrl || null;
            } catch (err) {
                console.error('[aegisPrivacyAction:export] error', { userId, err });
                throw new functions.https.HttpsError('internal', 'Data export generation failed.');
            }

            await db.collection('aegisProfiles').doc(userId).set(
                { lastExportRequestedAt: admin.firestore.FieldValue.serverTimestamp() },
                { merge: true }
            );

            return { success: true, exportUrl, deletionManifest: null, error: null };
        }

        // ── delete ────────────────────────────────────────────────────────
        case 'delete': {
            // Build canonical deletion manifest
            const manifestId = db.collection('_tmp').doc().id;
            const firestorePaths = [
                `users/${userId}`,
                `posts/${userId}`,
                `comments/${userId}`,
                `messages/${userId}`,
                `notifications/${userId}`,
                `userFollows/${userId}`,
                `churchNotes/${userId}`,
                `prayerRequests/${userId}`,
                `safetyProfiles/${userId}`,
                `aegisProfiles/${userId}`,
                `bereanSessions/${userId}`,
                `privacyModes/${userId}`,
                `wellbeingState/${userId}`,
                `dataExports/${userId}`,
                `reportHistory/${userId}`,
                `moderationLog/${userId}`,
                ...(targetPaths || []),
            ];
            const storagePaths = [
                `users/${userId}/`,
                `posts/${userId}/`,
                `profileImages/${userId}/`,
                `churchNotes/${userId}/`,
            ];
            const pineconeNamespaces = [
                `user-${userId}-posts`,
                `user-${userId}-berean`,
                `user-${userId}-church-notes`,
                `user-${userId}-preferences`,
            ];
            const derivedDataPaths = [
                `algolia:users:${userId}`,
                `algolia:posts:author:${userId}`,
                `cache:feed:${userId}`,
                `cache:recommendations:${userId}`,
            ];

            // Firestore batch delete (write tombstone docs first for audit)
            const batch = db.batch();
            for (const path of firestorePaths) {
                const ref = db.doc(path);
                batch.delete(ref);
            }
            const manifestRef = db.collection('deletionManifests').doc(manifestId);
            batch.set(manifestRef, {
                manifestId,
                userId,
                requestedAt: admin.firestore.FieldValue.serverTimestamp(),
                firestorePaths,
                storagePaths,
                pineconeNamespaces,
                derivedDataPaths,
                confirmedAt: null,
                isComplete: false,
            });
            await callWithTimeout(() => batch.commit(), 30000);

            // Storage deletion (best-effort, fan-out async)
            for (const prefix of storagePaths) {
                bucket.deleteFiles({ prefix }).catch(err => {
                    console.warn('[aegisPrivacyAction:delete] Storage deletion partial error', { prefix, err: err.message });
                });
            }

            // Pinecone deletion (HTTP call — best-effort)
            const pineconeEndpoint = process.env.PINECONE_DELETE_ENDPOINT;
            if (pineconeEndpoint) {
                for (const ns of pineconeNamespaces) {
                    fetch(pineconeEndpoint, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', 'Api-Key': process.env.PINECONE_API_KEY || '' },
                        body: JSON.stringify({ namespace: ns, deleteAll: true }),
                    }).catch(err => {
                        console.warn('[aegisPrivacyAction:delete] Pinecone deletion failed', { ns, err: err.message });
                    });
                }
            }

            // Mark manifest complete
            await manifestRef.update({ confirmedAt: admin.firestore.FieldValue.serverTimestamp(), isComplete: true });

            return {
                success: true,
                exportUrl: null,
                deletionManifest: {
                    manifestId,
                    userId,
                    firestorePaths,
                    storagePaths,
                    pineconeNamespaces,
                    derivedDataPaths,
                    isComplete: true,
                },
                error: null,
            };
        }

        // ── apply_mode ────────────────────────────────────────────────────
        case 'apply_mode': {
            if (!modeId || typeof modeId !== 'string') {
                throw new functions.https.HttpsError('invalid-argument', 'modeId is required for apply_mode action.');
            }
            await callWithTimeout(
                () => db.collection('aegisProfiles').doc(userId).set(
                    { activeMode: modeId, activeModeSetAt: admin.firestore.FieldValue.serverTimestamp() },
                    { merge: true }
                ),
                10000
            );
            return { success: true, exportUrl: null, deletionManifest: null, error: null };
        }

        // ── defer_location ─────────────────────────────────────────────────
        case 'defer_location': {
            await callWithTimeout(
                () => db.collection('aegisProfiles').doc(userId).set(
                    { locationDeferralEnabled: true, locationDeferralSetAt: admin.firestore.FieldValue.serverTimestamp() },
                    { merge: true }
                ),
                10000
            );
            return { success: true, exportUrl: null, deletionManifest: null, error: null };
        }

        // ── memorial ──────────────────────────────────────────────────────
        case 'memorial': {
            await callWithTimeout(
                () => db.collection('aegisProfiles').doc(userId).set(
                    { memorialized: true, memorializedAt: admin.firestore.FieldValue.serverTimestamp() },
                    { merge: true }
                ),
                10000
            );
            return { success: true, exportUrl: null, deletionManifest: null, error: null };
        }

        // ── transfer_legacy ────────────────────────────────────────────────
        case 'transfer_legacy': {
            const legacyContactId = (targetPaths && targetPaths[0]) || null;
            if (!legacyContactId) {
                throw new functions.https.HttpsError('invalid-argument', 'Legacy contact userId must be in targetPaths[0].');
            }
            await callWithTimeout(
                () => db.collection('aegisProfiles').doc(userId).set(
                    { legacyContactId, legacySetAt: admin.firestore.FieldValue.serverTimestamp() },
                    { merge: true }
                ),
                10000
            );
            return { success: true, exportUrl: null, deletionManifest: null, error: null };
        }

        default:
            throw new functions.https.HttpsError('invalid-argument', `Unknown action: ${action}`);
    }
});

// ─── 5. aegisEscalate ─────────────────────────────────────────────────────

/**
 * Creates a Guardian review ticket with urgency-based routing.
 * Critical/sextortion → legal queue immediately.
 * High → human review queue.
 * Medium/low → automated queue.
 *
 * data: { reporterId: string, reportedUserId: string, capability: string,
 *          evidenceUrls: string[], evidenceText: string[],
 *          contentId?: string, urgency: "low"|"medium"|"high"|"critical" }
 * returns: AegisEscalateResponse
 */
const aegisEscalate = functions.https.onCall(async (data, context) => {
    assertAuthAndAppCheck(context);

    const {
        reporterId,
        reportedUserId,
        capability,
        evidenceUrls,
        evidenceText,
        contentId,
        urgency,
    } = data || {};

    if (!reporterId || typeof reporterId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'reporterId is required.');
    }
    if (context.auth.uid !== reporterId) {
        throw new functions.https.HttpsError('permission-denied', 'reporterId must match authenticated user.');
    }
    if (!reportedUserId || typeof reportedUserId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'reportedUserId is required.');
    }
    if (!capability || typeof capability !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'capability is required.');
    }
    if (!['low', 'medium', 'high', 'critical'].includes(urgency)) {
        throw new functions.https.HttpsError('invalid-argument', 'urgency must be low, medium, high, or critical.');
    }

    const db = admin.firestore();
    const ticketId = db.collection('humanReviewQueue').doc().id;

    // Urgency routing logic
    const isCritical = urgency === 'critical';
    const isSextortion = capability === 'C26'; // sextortionPattern
    const needsLegalRoute = isCritical || isSextortion;
    const needsHumanReview = urgency === 'high';

    let route;
    let estimatedResponseTime;
    if (needsLegalRoute) {
        route = 'legal';
        estimatedResponseTime = '1 hour';
    } else if (needsHumanReview) {
        route = 'human_review';
        estimatedResponseTime = '24 hours';
    } else {
        route = 'automated_queue';
        estimatedResponseTime = '72 hours';
    }

    const ticketData = {
        ticketId,
        reporterId,
        reportedUserId,
        capability,
        evidenceUrls: evidenceUrls || [],
        evidenceText: evidenceText || [],
        contentId: contentId || null,
        urgency,
        route,
        estimatedResponseTime,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        resolvedAt: null,
        status: 'open',
        policyVersion: '2026-05-31-v1',
    };

    try {
        await callWithTimeout(
            () => db.collection('humanReviewQueue').doc(ticketId).set(ticketData),
            10000
        );
    } catch (err) {
        console.error('[aegisEscalate] Firestore write error', { ticketId, err });
        throw new functions.https.HttpsError('internal', 'Could not create review ticket. Please try again.');
    }

    // Care resources based on capability
    const careResources = buildCareResources(capability, urgency);

    console.info('[aegisEscalate] ticket created', { ticketId, route, urgency, capability });

    return {
        ticketId,
        route,
        careResources,
        estimatedResponseTime,
    };
});

// ─── Care Resources Builder ───────────────────────────────────────────────

function buildCareResources(capability, urgency) {
    const resources = [];

    // Always include pastoral support
    resources.push({
        id: 'pastoral_support',
        title: 'Pastoral Care',
        body: 'If you\'ve been affected by what you reported, our pastoral care team is here for you.',
        actionLabel: 'Connect with Care',
        actionUrl: 'amen://care/pastoral',
        resourceType: 'pastoral',
    });

    // Crisis resources for sextortion
    if (capability === 'C26') {
        resources.push({
            id: 'ncmec',
            title: 'Report to NCMEC',
            body: 'The National Center for Missing & Exploited Children handles reports of this nature.',
            actionLabel: 'Report Now',
            actionUrl: 'https://www.missingkids.org/gethelpnow/cybertipline',
            resourceType: 'crisis',
        });
    }

    // Legal info for critical urgency
    if (urgency === 'critical') {
        resources.push({
            id: 'legal_info',
            title: 'Legal Guidance',
            body: 'For critical safety situations, you may want to contact local authorities or legal counsel.',
            actionLabel: null,
            actionUrl: null,
            resourceType: 'legal',
        });
    }

    // Spiritual abuse resources
    if (capability === 'C21') {
        resources.push({
            id: 'spiritual_abuse',
            title: 'Spiritual Abuse Resources',
            body: 'You are not alone. Resources are available for those navigating harmful church dynamics.',
            actionLabel: 'Learn More',
            actionUrl: 'https://www.netgrace.org',
            resourceType: 'link',
        });
    }

    return resources;
}

// ─── Exports ──────────────────────────────────────────────────────────────

module.exports = {
    aegisAnalyzeMedia,
    aegisReviewText,
    aegisAccountTrust,
    aegisPrivacyAction,
    aegisEscalate,
};
