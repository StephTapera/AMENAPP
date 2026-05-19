'use strict';

const onCall = jest.fn((options, handler) => handler);
const onRequest = jest.fn((options, handler) => handler);

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
    this.name = 'HttpsError';
  }
}

module.exports = { onCall, onRequest, HttpsError };
