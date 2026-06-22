import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import StripeConstructor from "stripe";

const stripeSecretKeyParam = defineSecret("STRIPE_SECRET_KEY");
const stripeCovenantWebhookSecret = defineSecret("STRIPE_COVENANT_WEBHOOK_SECRET");

// ── Types ─────────────────────────────────────────────────────────────────────

type MemberStatus = "active" | "trialing" | "cancelled" | "past_due";
type StripeSubscriptionStatus = "active" | "trialing" | "canceled" | "past_due" | string;
type StripeMetadata = Record<string, string>;
type StripeSubscriptionObject = {
    id: string;
    status: StripeSubscriptionStatus;
    metadata?: StripeMetadata | null;
    customer: string | { id: string };
};
type StripeCheckoutSessionObject = {
    id: string;
    mode?: string | null;
    subscription?: string | StripeSubscriptionObject | null;
    customer?: string | { id: string } | null;
    metadata?: StripeMetadata | null;
};
type StripeEventObject = {
    type: string;
    data: { object: unknown };
};
type StripeClient = InstanceType<typeof StripeConstructor>;

interface MemberIndexFields {
    userId: string;
    covenantId: string;
    status: MemberStatus;
    role: string;
    source: "stripe_subscription";
    stripeCustomerId: string;
    stripeSubscriptionId: string;
    activatedAt?: admin.firestore.FieldValue;
    indexedAt: admin.firestore.FieldValue;
    updatedAt: admin.firestore.FieldValue;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function memberStatusFromStripe(
    stripeStatus: StripeSubscriptionStatus
): MemberStatus | null {
    switch (stripeStatus) {
        case "active":   return "active";
        case "trialing": return "trialing";
        case "canceled": return "cancelled";
        case "past_due": return "past_due";
        // incomplete / incomplete_expired / unpaid — do not grant access
        default:         return null;
    }
}

function isGrantingAccess(status: MemberStatus | null): boolean {
    return status === "active" || status === "trialing";
}

// Checks both metadata key conventions (camelCase and snake_case).
function extractMetadata(
    metadata: StripeMetadata | null | undefined
): { covenantId: string | null; userId: string | null } {
    if (!metadata) return { covenantId: null, userId: null };
    return {
        covenantId: metadata["covenantId"] ?? metadata["covenant_id"] ?? null,
        userId:     metadata["userId"]     ?? metadata["user_id"]     ?? metadata["uid"] ?? null,
    };
}

// ── Core membership write (exported for unit testing) ─────────────────────────

export async function writeMemberIndex(params: {
    db: admin.firestore.Firestore;
    covenantId: string;
    userId: string;
    stripeStatus: StripeSubscriptionStatus;
    stripeCustomerId: string;
    stripeSubscriptionId: string;
}): Promise<void> {
    const { db, covenantId, userId, stripeStatus, stripeCustomerId, stripeSubscriptionId } = params;

    const memberStatus = memberStatusFromStripe(stripeStatus);
    if (!memberStatus) {
        logger.warn("[stripeCovenantWebhook] Unrecognised subscription status — skipping index write", {
            covenantId, userId, stripeStatus,
        });
        return;
    }

    const memberIndexRef = db
        .collection("covenants").doc(covenantId)
        .collection("members").doc(userId);

    // Preserve existing role so admin/moderator/creator ranks are never downgraded by a webhook.
    const existing = await memberIndexRef.get();
    const existingRole: string = existing.exists ? (existing.data()?.role ?? "member") : "member";

    const now = admin.firestore.FieldValue.serverTimestamp();
    const transitioning = isGrantingAccess(memberStatus) &&
        (!existing.exists || !isGrantingAccess(existing.data()?.status ?? null));

    const payload: MemberIndexFields = {
        userId,
        covenantId,
        status: memberStatus,
        role: existingRole,
        source: "stripe_subscription",
        stripeCustomerId,
        stripeSubscriptionId,
        indexedAt: now,
        updatedAt: now,
    };

    // Only stamp activatedAt on first grant (or reactivation after cancellation).
    if (transitioning) {
        payload.activatedAt = now;
    }

    await memberIndexRef.set(payload, { merge: true });
}

// ── Core event dispatch (exported for unit testing) ───────────────────────────

export async function handleStripeEvent(
    event: StripeEventObject,
    db: admin.firestore.Firestore,
    stripe: Pick<StripeClient, "subscriptions">
): Promise<void> {
    switch (event.type) {

        case "checkout.session.completed": {
            const session = event.data.object as StripeCheckoutSessionObject;
            if (session.mode !== "subscription" || !session.subscription) return;

            const subscriptionId = typeof session.subscription === "string"
                ? session.subscription
                : (session.subscription as StripeSubscriptionObject).id;

            // Retrieve full subscription to get live status + metadata.
            const subscription = await stripe.subscriptions.retrieve(subscriptionId);

            // metadata can be on the subscription OR the session; subscription wins.
            const { covenantId, userId } = extractMetadata(
                Object.keys(subscription.metadata ?? {}).length > 0
                    ? subscription.metadata
                    : session.metadata
            );

            if (!covenantId || !userId) {
                logger.warn("[stripeCovenantWebhook] checkout.session.completed: missing covenantId/userId metadata", {
                    sessionId: session.id, subscriptionId,
                });
                return;
            }

            await writeMemberIndex({
                db,
                covenantId,
                userId,
                stripeStatus: subscription.status,
                stripeCustomerId: typeof session.customer === "string"
                    ? session.customer
                    : (session.customer as { id: string } | null)?.id ?? "",
                stripeSubscriptionId: subscriptionId,
            });

            logger.info("[stripeCovenantWebhook] Member index written after checkout", { covenantId, userId });
            return;
        }

        case "customer.subscription.created":
        case "customer.subscription.updated": {
            const subscription = event.data.object as StripeSubscriptionObject;
            const { covenantId, userId } = extractMetadata(subscription.metadata);

            if (!covenantId || !userId) {
                logger.warn(`[stripeCovenantWebhook] ${event.type}: missing covenantId/userId metadata`, {
                    subscriptionId: subscription.id,
                });
                return;
            }

            await writeMemberIndex({
                db,
                covenantId,
                userId,
                stripeStatus: subscription.status,
                stripeCustomerId: typeof subscription.customer === "string"
                    ? subscription.customer
                    : (subscription.customer as { id: string }).id,
                stripeSubscriptionId: subscription.id,
            });

            logger.info(`[stripeCovenantWebhook] Member index updated for ${event.type}`, {
                covenantId, userId, status: subscription.status,
            });
            return;
        }

        case "customer.subscription.deleted": {
            const subscription = event.data.object as StripeSubscriptionObject;
            const { covenantId, userId } = extractMetadata(subscription.metadata);

            if (!covenantId || !userId) {
                logger.warn("[stripeCovenantWebhook] customer.subscription.deleted: missing metadata", {
                    subscriptionId: subscription.id,
                });
                return;
            }

            // Mark cancelled — never delete the doc; preserve role for potential reactivation.
            const now = admin.firestore.FieldValue.serverTimestamp();
            await db
                .collection("covenants").doc(covenantId)
                .collection("members").doc(userId)
                .set({
                    status: "cancelled",
                    updatedAt: now,
                    stripeSubscriptionId: subscription.id,
                }, { merge: true });

            logger.info("[stripeCovenantWebhook] Member marked cancelled", { covenantId, userId });
            return;
        }

        default:
            // Unhandled event type — acknowledge silently.
            return;
    }
}

// ── Cloud Function ────────────────────────────────────────────────────────────

export const stripeCovenantWebhook = onRequest(
    { region: "us-central1", secrets: [stripeSecretKeyParam, stripeCovenantWebhookSecret] },
    async (req, res) => {
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        const stripeSecretKey    = stripeSecretKeyParam.value();
        const webhookSecret      = stripeCovenantWebhookSecret.value();

        if (!stripeSecretKey || !webhookSecret) {
            logger.error("[stripeCovenantWebhook] Missing Stripe credentials in environment");
            res.status(500).send("Server configuration error");
            return;
        }

        const stripe = new StripeConstructor(stripeSecretKey, { apiVersion: "2026-05-27.dahlia" });
        const signature = req.headers["stripe-signature"] as string | undefined;

        let event: StripeEventObject;
        try {
            event = stripe.webhooks.constructEvent(
                (req as unknown as { rawBody: Buffer }).rawBody,
                signature ?? "",
                webhookSecret
            );
        } catch (err) {
            logger.warn("[stripeCovenantWebhook] Webhook signature verification failed", { err });
            res.status(400).send("Webhook signature verification failed");
            return;
        }

        try {
            await handleStripeEvent(event, admin.firestore(), stripe);
            res.status(200).json({ received: true });
        } catch (err) {
            logger.error("[stripeCovenantWebhook] Error processing webhook event", {
                eventType: event.type, err,
            });
            res.status(500).send("Internal error processing webhook");
        }
    }
);
