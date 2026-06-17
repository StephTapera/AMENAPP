// Jest manual mock for the 'stripe' npm package.
// The actual Stripe SDK is never instantiated during unit tests —
// stripeCovenantWebhook.test.ts calls handleStripeEvent directly,
// bypassing the HTTP layer and signature verification.

const mockSessionsCreate = jest.fn();

const Stripe = jest.fn().mockImplementation(() => ({
    checkout: {
        sessions: {
            create: mockSessionsCreate,
        },
    },
    webhooks: {
        constructEvent: jest.fn(),
    },
    subscriptions: {
        retrieve: jest.fn(),
    },
}));

module.exports = Stripe;
module.exports.default = Stripe;
module.exports.__mockSessionsCreate = mockSessionsCreate;
