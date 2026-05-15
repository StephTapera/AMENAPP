// Jest manual mock for the 'stripe' npm package.
// The actual Stripe SDK is never instantiated during unit tests —
// stripeCovenantWebhook.test.ts calls handleStripeEvent directly,
// bypassing the HTTP layer and signature verification.

const Stripe = jest.fn().mockImplementation(() => ({
    webhooks: {
        constructEvent: jest.fn(),
    },
    subscriptions: {
        retrieve: jest.fn(),
    },
}));

module.exports = Stripe;
module.exports.default = Stripe;
