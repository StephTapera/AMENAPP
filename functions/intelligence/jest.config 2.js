/**
 * Jest config for Living Intelligence formation tests.
 * Uses plain JS (CommonJS), no TypeScript transform needed.
 */
module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/intelligence/tests/**/*.test.js'],
  transform: {},
  moduleFileExtensions: ['js', 'json'],
};
