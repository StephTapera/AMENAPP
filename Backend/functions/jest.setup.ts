// Shared Jest setup (2026-06-10, dormant-test sweep).
//
// Central mock for the firebase-functions logger so suites that assert on it
// (e.g. previewLogger) don't each have to wire `jest.mock(...)`. ALL other
// firebase-functions exports (onCall, HttpsError, scheduler, etc.) are preserved
// via requireActual, so callable/trigger imports keep working unchanged.

const loggerMock = {
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
  write: jest.fn(),
};

jest.mock("firebase-functions", () => ({
  ...jest.requireActual("firebase-functions"),
  logger: loggerMock,
}));

jest.mock("firebase-functions/v2", () => ({
  ...jest.requireActual("firebase-functions/v2"),
  logger: loggerMock,
}));

jest.mock("firebase-functions/logger", () => loggerMock);

// Note: suites that need isolated call history already call jest.clearAllMocks()
// in their own beforeEach. This file runs as a `setupFiles` module (before the
// test framework is installed), so it only registers module mocks.
