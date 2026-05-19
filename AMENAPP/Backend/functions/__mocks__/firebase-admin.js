'use strict';

const mockTimestamp = { toDate: () => new Date(), toMillis: () => Date.now() };

const mockFirestore = {
  collection: jest.fn().mockReturnThis(),
  doc: jest.fn().mockReturnThis(),
  get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }),
  set: jest.fn().mockResolvedValue(undefined),
  runTransaction: jest.fn().mockImplementation(async (fn) => {
    const tx = {
      get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }),
      set: jest.fn(),
    };
    return fn(tx);
  }),
};

const admin = {
  firestore: jest.fn(() => mockFirestore),
  auth: jest.fn(() => ({
    verifyIdToken: jest.fn().mockResolvedValue({ uid: 'test-uid-123' }),
  })),
  appCheck: jest.fn(() => ({
    verifyToken: jest.fn().mockResolvedValue({ appId: 'test-app' }),
  })),
  app: jest.fn(() => ({
    functions: jest.fn(() => ({
      httpsCallable: jest.fn(() => jest.fn().mockResolvedValue({ data: {} })),
    })),
  })),
  initializeApp: jest.fn(),
};

admin.firestore.FieldValue = {
  serverTimestamp: jest.fn(() => ({ _methodName: 'serverTimestamp' })),
  increment: jest.fn((n) => ({ _methodName: 'increment', operand: n })),
  arrayUnion: jest.fn((...args) => ({ _methodName: 'arrayUnion', elements: args })),
  arrayRemove: jest.fn((...args) => ({ _methodName: 'arrayRemove', elements: args })),
};

admin.firestore.Timestamp = {
  fromMillis: jest.fn((ms) => ({ seconds: Math.floor(ms / 1000), nanoseconds: 0, ...mockTimestamp })),
  fromDate: jest.fn((date) => ({ seconds: Math.floor(date.getTime() / 1000), nanoseconds: 0, ...mockTimestamp })),
  now: jest.fn(() => mockTimestamp),
};

module.exports = admin;
module.exports.default = admin;
