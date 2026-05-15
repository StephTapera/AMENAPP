const logger = {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
    log: jest.fn(),
    write: jest.fn(),
};

// v1 compat surface used by trustIntelligence.ts (functions.https.onCall, functions.https.HttpsError)
const https = {
    onCall: jest.fn((handler) => handler),
    HttpsError: class HttpsError extends Error {
        constructor(code, message) {
            super(message);
            this.code = code;
        }
    },
};

module.exports = { logger, https };
