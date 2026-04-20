// benevolenceModeration.ts
// AMEN Giving — Firestore trigger for benevolence request moderation pipeline.
// On create: Guardian AI → human escalation if needed.
// On update: tracks lifecycle transitions and sends restrained notifications.

import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { guardianReview } from '../services/BenevolenceGuardian';

const db = admin.firestore();
const messaging = admin.messaging();

// ─── onBenevolenceRequestCreated ─────────────────────────────────────────────
export const onBenevolenceRequestCreated = onDocumentCreated(
  'benevolence_requests/{requestId}',
  async (event) => {
    const request = event.data?.data();
    const requestId = event.params.requestId;
    if (!request) return;

    // Already Guardian-reviewed at submission time (via callable).
    // If it came from a different path (admin SDK), run review now.
    if (!request.guardianStatus || request.guardianStatus === 'pending') {
      const result = await guardianReview(
        { title: request.title, summary: request.summary, requestedAmount: request.requestedAmount, category: request.category },
        request.requesterUserId,
        db
      );

      await event.data!.ref.update({
        guardianStatus: result.decision === 'escalate_human' ? 'escalated' : result.decision,
        guardianFlags: result.riskFlags,
        status: result.decision === 'cleared'
          ? 'verification_pending'
          : 'guardian_review',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (result.decision === 'escalate_human') {
        await createHumanReviewTask(requestId, request, result.reasons);
      }
    }

    // Notify the requester their submission was received (calm, no pressure)
    await sendRequesterNotification(
      request.requesterUserId,
      'Request submitted',
      'Your request has been received and is under review.',
      { type: 'benevolence_request_submitted', requestId }
    );
  }
);

// ─── onBenevolenceRequestUpdated ─────────────────────────────────────────────
export const onBenevolenceRequestUpdated = onDocumentUpdated(
  'benevolence_requests/{requestId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const requestId = event.params.requestId;
    if (!before || !after) return;

    // Status changed → approved
    if (before.status !== 'approved' && after.status === 'approved') {
      await sendRequesterNotification(
        after.requesterUserId,
        'Request approved',
        'Your request has been approved and is now active.',
        { type: 'benevolence_request_approved', requestId }
      );
    }

    // Status changed → fulfilled
    if (before.fulfillmentState !== 'fully_funded' && after.fulfillmentState === 'fully_funded') {
      await event.data!.after.ref.update({
        status: 'fulfilled',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await sendRequesterNotification(
        after.requesterUserId,
        'Request fulfilled',
        'Your request has been fully funded. Please submit follow-up receipts when available.',
        { type: 'benevolence_request_fulfilled', requestId }
      );
    }
  }
);

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function createHumanReviewTask(
  requestId: string,
  request: any,
  reasons: string[]
): Promise<void> {
  await db.collection('moderation_queue').add({
    resourceType: 'benevolence_request',
    resourceId: requestId,
    userId: request.requesterUserId,
    priority: 'high',
    reasons,
    summary: request.summary,
    title: request.title,
    amount: request.requestedAmount,
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function sendRequesterNotification(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  const tokensSnap = await db.collection('deviceTokens')
    .where('userId', '==', userId)
    .get();

  const tokens = tokensSnap.docs.map(d => d.data().token as string).filter(Boolean);
  if (tokens.length === 0) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { ...data, source: 'amen_giving' },
    apns: {
      payload: {
        aps: {
          badge: 1,
          sound: 'default',
        },
      },
    },
  });
}
