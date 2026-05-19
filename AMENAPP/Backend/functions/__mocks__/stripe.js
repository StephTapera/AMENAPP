'use strict';
const Stripe = jest.fn(() => ({
  customers: { create: jest.fn(), retrieve: jest.fn() },
  paymentIntents: { create: jest.fn() },
  webhooks: { constructEvent: jest.fn() },
}));
module.exports = Stripe;
module.exports.default = Stripe;
