'use strict';
class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
const https = { onCall: jest.fn((handler) => handler), HttpsError };
const logger = { info: jest.fn(), warn: jest.fn(), error: jest.fn(), log: jest.fn() };
module.exports = { https, logger, HttpsError };
