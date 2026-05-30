/**
 * stripeHelper.ts
 *
 * Re-exports Stripe types using InstanceType<typeof Stripe> derivation,
 * which works with the CJS `export = StripeConstructor` declaration in stripe v22.
 *
 * Import from here instead of using `Stripe.Event`, `Stripe.Subscription`, etc.
 * directly (those fail because the CJS namespace wrapper doesn't expose them).
 */
import Stripe = require("stripe");

type StripeInst = InstanceType<typeof Stripe>;

export type StripeEvent = ReturnType<StripeInst["webhooks"]["constructEvent"]>;

export type StripeSubscription = Awaited<
  ReturnType<StripeInst["subscriptions"]["retrieve"]>
>;

export type StripeCheckoutSession = Awaited<
  ReturnType<StripeInst["checkout"]["sessions"]["retrieve"]>
>;

export type StripeCustomer = Extract<
  Awaited<ReturnType<StripeInst["customers"]["retrieve"]>>,
  { object: "customer" }
>;

export type StripePaymentIntent = Awaited<
  ReturnType<StripeInst["paymentIntents"]["retrieve"]>
>;

export type StripeInvoice = Awaited<
  ReturnType<StripeInst["invoices"]["retrieve"]>
>;

export type StripeMetadata = Record<string, string | undefined>;

export type StripeMetadataParam = Record<string, string>;

export type StripeSubscriptionStatus = StripeSubscription["status"];

export type StripeInstance = InstanceType<typeof Stripe>;

export { Stripe };
