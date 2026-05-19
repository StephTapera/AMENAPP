'use strict';

const defineSecret = jest.fn((name) => ({
  value: jest.fn(() => `mock-secret-${name}`),
}));

const defineString = jest.fn((name) => ({
  value: jest.fn(() => `mock-string-${name}`),
}));

module.exports = { defineSecret, defineString };
