// Ensure AI provider env vars are non-empty so generation branches execute.
// Actual network calls are blocked by the global fetch mock in each test suite.
process.env.GROK_API_KEY = "test-grok-key-do-not-use";
process.env.XAI_API_KEY = "test-xai-key-do-not-use";
process.env.ANTHROPIC_API_KEY = "test-anthropic-key-do-not-use";

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

jest.mock("firebase-functions/v2/https", () => {
  class HttpsError extends Error {
    code: string;
    details?: unknown;

    constructor(code: string, message: string, details?: unknown) {
      super(message);
      this.code = code;
      this.details = details;
    }
  }

  const unwrapHandler = (optionsOrHandler: unknown, maybeHandler?: unknown) => (
    typeof optionsOrHandler === "function" ? optionsOrHandler : maybeHandler
  );

  return {
    HttpsError,
    onCall: jest.fn(unwrapHandler),
    onRequest: jest.fn(unwrapHandler),
  };
});

jest.mock("firebase-functions/logger", () => loggerMock);

// firebase-functions/v2/firestore: strip the trigger wrapper so Firestore trigger
// exports are plain async functions directly callable in tests.
jest.mock("firebase-functions/v2/firestore", () => {
  const passthrough = (_pathOrOptions: unknown, handler?: unknown) =>
    typeof _pathOrOptions === "function" ? _pathOrOptions : handler;
  return {
    onDocumentCreated: jest.fn(passthrough),
    onDocumentDeleted: jest.fn(passthrough),
    onDocumentUpdated: jest.fn(passthrough),
    onDocumentWritten: jest.fn(passthrough),
  };
});

// firebase-functions/params: return jest mocks so tests can spy on .value()
// and call .mockReturnValue() when simulating missing secrets.
jest.mock("firebase-functions/params", () => ({
  defineSecret: jest.fn((name: string) => ({
    name,
    value: jest.fn(() => `mock-${name}-value`),
  })),
  defineInt: jest.fn((name: string, options?: { default?: number }) => ({
    name,
    value: jest.fn(() => options?.default ?? 0),
  })),
  defineString: jest.fn((name: string, options?: { default?: string }) => ({
    name,
    value: jest.fn(() => options?.default ?? ""),
  })),
}));

// Note: suites that need isolated call history already call jest.clearAllMocks()
// in their own beforeEach. This file runs as a `setupFiles` module (before the
// test framework is installed), so it only registers module mocks.
