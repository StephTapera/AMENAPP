/**
 * processGivingCharge.ts
 *
 * Server-side Stripe charge processing for in-app giving.
 * Called after Apple Pay or card tokenization on the client.
 *
 * Security:
 * - Requires Firebase Auth + App Check
 * - Rate limited
 * - Amount validated server-side (never trusted from client)
 * - Nonprofit ID validated against allowlist
 * - Stripe keys never exposed to client
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {requireAuthAndAppCheck} from "../amenAI/common";
import {enforceRateLimit} from "../rateLimit";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const db = getFirestore();

const GIVING_RATE_LIMIT = {name: "giving_1hr", windowMs: 3_600_000, maxCalls: 10};

// Minimum and maximum donation bounds (in cents)
const MIN_AMOUNT_CENTS = 100;     // $1.00
const MAX_AMOUNT_CENTS = 100_000; // $1,000.00

interface GivingChargeInput {
    nonprofitId: string;
    amountCents: number;
    currency: string;
    paymentToken: string;      // Apple Pay / Stripe token from client
    recurringMode: "oneTime" | "monthly" | "annually";
    coverFee: boolean;
}

export const processGivingCharge = onCall(
    {enforceAppCheck: true, secrets: [stripeSecretKey]},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, [GIVING_RATE_LIMIT]);

        const {nonprofitId, amountCents, currency = "usd",
            paymentToken, recurringMode = "oneTime", coverFee = false} =
            (request.data ?? {}) as Partial<GivingChargeInput>;

        // ── 1. Input validation ───────────────────────────────────────────
        if (!nonprofitId || typeof nonprofitId !== "string") {
            throw new HttpsError("invalid-argument", "nonprofitId is required.");
        }
        if (!paymentToken || typeof paymentToken !== "string") {
            throw new HttpsError("invalid-argument", "paymentToken is required.");
        }
        if (typeof amountCents !== "number" ||
            amountCents < MIN_AMOUNT_CENTS ||
            amountCents > MAX_AMOUNT_CENTS) {
            throw new HttpsError("invalid-argument",
                `Amount must be between $${MIN_AMOUNT_CENTS / 100} and $${MAX_AMOUNT_CENTS / 100}.`);
        }

        // ── 2. Verify nonprofit exists and is giving-enabled ─────────────
        const nonprofitSnap = await db.collection("nonprofits").doc(nonprofitId).get();
        if (!nonprofitSnap.exists) {
            throw new HttpsError("not-found", "Nonprofit not found.");
        }
        const nonprofit = nonprofitSnap.data()!;
        if (!nonprofit.givingEnabled) {
            throw new HttpsError("failed-precondition",
                "This organization has not enabled in-app giving.");
        }
        const stripeAccountId = nonprofit.stripeConnectedAccountId as string | undefined;
        if (!stripeAccountId) {
            throw new HttpsError("failed-precondition",
                "This organization is not configured for payments yet.");
        }

        // ── 3. Apply platform fee if not covered ──────────────────────────
        const platformFeeCents = coverFee ? 0 : Math.round(amountCents * 0.029 + 30);
        const totalCents = amountCents + platformFeeCents;

        const key = stripeSecretKey.value();
        if (!key) {
            logger.error("[processGivingCharge] STRIPE_SECRET_KEY not configured");
            throw new HttpsError("internal", "Payment service not configured.");
        }

        // ── 4. Call Stripe ────────────────────────────────────────────────
        // Use raw fetch to avoid bundling Stripe SDK (matches codebase pattern).
        const isRecurring = recurringMode !== "oneTime";

        let chargeResponse: Response;
        if (isRecurring) {
            // Create a Stripe Customer + Subscription for recurring giving
            chargeResponse = await fetch("https://api.stripe.com/v1/subscriptions", {
                method: "POST",
                headers: {
                    "Authorization": `Bearer ${key}`,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
                body: new URLSearchParams({
                    "customer_email": nonprofit.contactEmail ?? "",
                    "items[0][price_data][currency]": currency,
                    "items[0][price_data][product_data][name]": `Giving to ${nonprofit.name}`,
                    "items[0][price_data][unit_amount]": String(totalCents),
                    "items[0][price_data][recurring][interval]":
                        recurringMode === "monthly" ? "month" : "year",
                    "payment_behavior": "default_incomplete",
                    "metadata[nonprofitId]": nonprofitId,
                    "metadata[donorUid]": uid,
                    "transfer_data[destination]": stripeAccountId,
                }).toString(),
            });
        } else {
            // One-time charge via PaymentIntent
            chargeResponse = await fetch("https://api.stripe.com/v1/payment_intents", {
                method: "POST",
                headers: {
                    "Authorization": `Bearer ${key}`,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
                body: new URLSearchParams({
                    "amount": String(totalCents),
                    "currency": currency,
                    "payment_method": paymentToken,
                    "confirm": "true",
                    "transfer_data[destination]": stripeAccountId,
                    "metadata[nonprofitId]": nonprofitId,
                    "metadata[donorUid]": uid,
                    "description": `Donation to ${nonprofit.name}`,
                }).toString(),
            });
        }

        if (!chargeResponse.ok) {
            const errText = await chargeResponse.text();
            logger.error("[processGivingCharge] Stripe error", {
                nonprofitId, uid, status: chargeResponse.status,
                // Never log the payment token or full error body in prod
                statusText: chargeResponse.statusText,
                errorBodyLength: errText.length,
            });
            throw new HttpsError("internal", "Payment could not be processed. Please try again.");
        }

        const chargeData = await chargeResponse.json() as {id: string; status?: string};

        // ── 5. Record giving event (for donor history, never shared) ──────
        await db.collection("users").doc(uid)
            .collection("givingHistory").add({
                nonprofitId,
                nonprofitName: nonprofit.name,
                amountCents,
                platformFeeCents,
                totalCents,
                currency,
                recurringMode,
                stripeChargeId: chargeData.id,
                status: chargeData.status ?? "processing",
                givenAt: FieldValue.serverTimestamp(),
            });

        logger.info("[processGivingCharge] Giving charge processed", {
            nonprofitId, uid, amountCents, recurringMode,
        });

        return {
            success: true,
            chargeId: chargeData.id,
            status: chargeData.status ?? "processing",
            amountCents,
            totalCents,
        };
    }
);
